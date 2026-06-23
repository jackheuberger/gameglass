defmodule Gameglass.Ingest do
  @moduledoc """
  Scheduler-agnostic ingestion pipeline. `refresh/1` performs one full crawl of
  the anonymous public catalog and reconciles it into the database:

    1. Enumerate the cloud catalog from the union of the "All games" SIGL and
       every subscription plan (the gallery SIGL alone omits ~35 cloud titles,
       e.g. EA Play games).
    2. Enrich each product (programs, pass metadata, price, XCloudTitleId).
    3. Keep cloud titles (those with a CLOUDGAMING offering), dedupe by streamable
       unit (XCloudTitleId).
    4. Compute the per-tier status matrix.
    5. Upsert a snapshot and append `ChangeEvent`s for any differences.

  It is intentionally free of any scheduling concern; a runner (GenServer, a
  manual trigger, or a job system) simply calls `refresh/1`.
  """

  import Ecto.Query

  alias Gameglass.Repo

  alias Gameglass.Catalog.{
    Client,
    Classifier,
    Game,
    Mapper,
    Product,
    Entitlement,
    TierStatus,
    ChangeEvent
  }

  require Logger

  @doc """
  Runs a full refresh. Returns `{:ok, summary}` or `{:error, reason}`.

  `summary` reports counts: `:enumerated`, `:from_sigl`, `:from_subscriptions`,
  `:enriched`, `:cloud_titles`, `:added`, `:removed`, `:changed`.
  """
  def refresh(opts \\ []) do
    market = Keyword.get(opts, :market, "US")
    started = System.monotonic_time(:millisecond)

    with {:ok, enumeration} <- Client.fetch_catalog_ids(opts),
         {:ok, raw} <- Client.fetch_products(enumeration.ids, opts) do
      records =
        raw
        |> Enum.flat_map(fn {pid, p} ->
          case Mapper.normalize(pid, p) do
            nil -> []
            rec -> [rec]
          end
        end)
        |> dedupe_by_key()

      present_ids = MapSet.new(enumeration.ids)

      result =
        Repo.transaction(
          fn -> reconcile(records, present_ids, market) end,
          timeout: :infinity
        )

      case result do
        {:ok, counts} ->
          summary =
            counts
            |> Map.merge(%{
              enumerated: length(enumeration.ids),
              from_sigl: enumeration.sigl,
              from_subscriptions: enumeration.subscriptions,
              enriched: map_size(raw),
              cloud_titles: length(records),
              duration_ms: System.monotonic_time(:millisecond) - started
            })

          Logger.info("Gameglass ingest complete: #{inspect(summary)}")
          {:ok, summary}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Collapses raw normalized records to one per streamable unit (XCloidTitleId).

  Several products (Standard/Deluxe/Premium editions) can share one streamable
  unit. The game is included on a tier if *any* edition is, so we merge pass
  metadata across the group and re-classify. The representative row (title,
  price, base product) is the edition with the richest pass metadata and lowest
  price — i.e. the standard edition. Exposed for testing.
  """
  def dedupe_by_key(records) do
    records
    |> Enum.group_by(& &1.game.dedup_key)
    |> Enum.map(&merge_group/1)
  end

  defp merge_group({_key, [single]}), do: single

  defp merge_group({_key, records}) do
    rep = Enum.min_by(records, &rep_rank/1)

    pass_ids = records |> Enum.flat_map(& &1.pass_ids) |> Enum.uniq()
    programs = records |> Enum.flat_map(& &1.programs) |> Enum.uniq()
    free? = Enum.any?(records, & &1.game.is_free)

    tier_statuses = Classifier.classify(programs, pass_ids, free?: free?)

    game = %{
      rep.game
      | programs: programs,
        is_free: free?,
        streamable: Classifier.streamable?(tier_statuses)
    }

    %{rep | game: game, tier_statuses: tier_statuses, pass_ids: pass_ids, programs: programs}
  end

  # Lower sorts first: prefer most pass metadata, then lowest price, then a
  # stable product-id tiebreak so selection is deterministic across runs.
  defp rep_rank(record) do
    {-length(record.pass_ids), record.game.price_value || 1.0e12, record.game.base_product_id}
  end

  defp reconcile(records, present_ids, market) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    existing = load_existing(market)

    events =
      Enum.flat_map(records, fn record ->
        upsert_record(record, existing[record.game.dedup_key], now)
      end)

    removal_events = mark_removed(existing, records, present_ids, now)

    all_events = events ++ removal_events
    insert_events(all_events, now)

    %{
      added: count_kind(all_events, "game_added"),
      removed: count_kind(all_events, "game_removed"),
      changed:
        Enum.count(
          all_events,
          &(&1.kind in ~w(tier_status_changed price_changed streamable_changed))
        )
    }
  end

  defp load_existing(market) do
    Game
    |> where([g], g.market == ^market)
    |> preload(:tier_statuses)
    |> Repo.all()
    |> Map.new(&{&1.dedup_key, &1})
  end

  # --- insert path -----------------------------------------------------------

  defp upsert_record(record, nil, now) do
    attrs =
      record.game
      |> Map.merge(%{first_seen_at: now, last_verified_at: now, last_changed_at: now})

    game = Repo.insert!(Game.changeset(%Game{}, attrs))

    Enum.each(record.tier_statuses, fn ts ->
      Repo.insert!(TierStatus.changeset(%TierStatus{}, Map.put(ts, :game_id, game.id)))
    end)

    upsert_product_link(record, game, now)

    [
      %{
        kind: "game_added",
        game_id: game.id,
        xcloud_title_id: game.xcloud_title_id || game.dedup_key,
        detail: game.title
      }
    ]
  end

  # --- update path -----------------------------------------------------------

  defp upsert_record(record, %Game{} = existing, now) do
    new = record.game

    status_events =
      tier_status_events(existing, record.tier_statuses, now)

    price_events =
      if existing.price_formatted != new.price_formatted do
        [event("price_changed", existing, existing.price_formatted, new.price_formatted, now)]
      else
        []
      end

    stream_events =
      if existing.streamable != new.streamable do
        [
          event(
            "streamable_changed",
            existing,
            to_string(existing.streamable),
            to_string(new.streamable),
            now
          )
        ]
      else
        []
      end

    changed? = status_events != [] or price_events != [] or stream_events != []

    attrs =
      new
      |> Map.put(:last_verified_at, now)
      |> maybe_put_changed(changed?, now)

    existing
    |> Game.changeset(attrs)
    |> Repo.update!()

    upsert_product_link(record, existing, now)

    status_events ++ price_events ++ stream_events
  end

  defp maybe_put_changed(attrs, true, now), do: Map.put(attrs, :last_changed_at, now)
  defp maybe_put_changed(attrs, false, _now), do: attrs

  defp tier_status_events(existing, new_statuses, now) do
    current = Map.new(existing.tier_statuses, &{&1.tier_key, &1.status})

    Enum.flat_map(new_statuses, fn ts ->
      old = Map.get(current, ts.tier_key)

      cond do
        is_nil(old) ->
          Repo.insert!(TierStatus.changeset(%TierStatus{}, Map.put(ts, :game_id, existing.id)))
          []

        old == ts.status ->
          []

        true ->
          from(t in TierStatus,
            where: t.game_id == ^existing.id and t.tier_key == ^ts.tier_key
          )
          |> Repo.update_all(set: [status: ts.status, updated_at: now])

          [
            %{
              kind: "tier_status_changed",
              game_id: existing.id,
              xcloud_title_id: existing.xcloud_title_id || existing.dedup_key,
              tier_key: ts.tier_key,
              old_value: old,
              new_value: ts.status,
              detail: existing.title
            }
          ]
      end
    end)
  end

  # --- removal path ----------------------------------------------------------

  defp mark_removed(existing, records, present_ids, now) do
    present_keys = MapSet.new(records, & &1.game.dedup_key)

    existing
    |> Map.values()
    |> Enum.filter(fn g ->
      g.streamable and not MapSet.member?(present_keys, g.dedup_key) and
        not MapSet.member?(present_ids, g.base_product_id)
    end)
    |> Enum.map(fn g ->
      from(game in Game, where: game.id == ^g.id)
      |> Repo.update_all(set: [streamable: false, last_changed_at: now, last_verified_at: now])

      %{
        kind: "game_removed",
        game_id: g.id,
        xcloud_title_id: g.xcloud_title_id || g.dedup_key,
        detail: g.title
      }
    end)
  end

  # --- products / entitlements ----------------------------------------------

  defp upsert_product_link(record, game, now) do
    g = record.game

    {:ok, product} =
      %Product{}
      |> Product.changeset(%{
        product_id: g.base_product_id,
        market: g.market,
        title: g.title,
        kind: "game",
        xcloud_title_id: g.xcloud_title_id,
        price_value: g.price_value,
        price_formatted: g.price_formatted,
        price_currency: g.price_currency,
        last_verified_at: now
      })
      |> Repo.insert(
        on_conflict:
          {:replace, [:title, :price_value, :price_formatted, :price_currency, :last_verified_at]},
        conflict_target: [:product_id, :market],
        returning: true
      )

    %Entitlement{}
    |> Entitlement.changeset(%{product_ref: product.id, game_id: game.id})
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:product_ref, :game_id])
  end

  # --- change events ---------------------------------------------------------

  defp event(kind, game, old, new, _now) do
    %{
      kind: kind,
      game_id: game.id,
      xcloud_title_id: game.xcloud_title_id || game.dedup_key,
      old_value: old,
      new_value: new,
      detail: game.title
    }
  end

  defp insert_events([], _now), do: :ok

  defp insert_events(events, now) do
    rows =
      Enum.map(events, fn e ->
        %{
          kind: e.kind,
          xcloud_title_id: Map.get(e, :xcloud_title_id),
          game_id: Map.get(e, :game_id),
          tier_key: Map.get(e, :tier_key),
          old_value: Map.get(e, :old_value),
          new_value: Map.get(e, :new_value),
          detail: Map.get(e, :detail),
          occurred_at: Map.get(e, :occurred_at, now),
          inserted_at: now,
          updated_at: now
        }
      end)

    rows
    |> Enum.chunk_every(500)
    |> Enum.each(&Repo.insert_all(ChangeEvent, &1))
  end

  defp count_kind(events, kind), do: Enum.count(events, &(&1.kind == kind))
end
