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
    Run,
    TierStatus,
    ChangeEvent
  }

  require Logger

  @doc """
  Runs a full refresh. Returns `{:ok, summary}` or `{:error, reason}`.

  Each call is recorded as an `ingestion_runs` row (running → success/failed) for
  transparency, and the first successful run acts as the baseline: games present
  then keep `added_at = nil` ("tracked since launch"), while games first seen in
  later runs get a genuine `added_at`.

  `summary` reports counts: `:enumerated`, `:from_sigl`, `:from_subscriptions`,
  `:enriched`, `:cloud_titles`, `:added`, `:removed`, `:changed`.
  """
  def refresh(opts \\ []) do
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

      meta = %{
        enumerated: length(enumeration.ids),
        from_sigl: enumeration.sigl,
        from_subscriptions: enumeration.subscriptions,
        enriched: map_size(raw)
      }

      ingest_records(records, MapSet.new(enumeration.ids), Keyword.put(opts, :meta, meta))
    end
  end

  @doc """
  Reconciles already-normalized records into the database within a recorded
  ingestion run. This is the network-free core of `refresh/1`: it creates the
  run row, applies the snapshot, and finalizes the run (success/failed).

  `present_ids` is the set of product ids seen this crawl (used to detect
  removals). `opts` may carry `:market` and a `:meta` map of enumeration counts.
  """
  def ingest_records(records, present_ids, opts \\ []) do
    market = Keyword.get(opts, :market, "US")
    meta = Keyword.get(opts, :meta, %{})
    started = System.monotonic_time(:millisecond)
    started_at = DateTime.utc_now() |> DateTime.truncate(:second)

    baseline? = not Repo.exists?(from(r in Run, where: r.status == "success"))
    run = Repo.insert!(Run.changeset(%Run{}, %{started_at: started_at, status: "running"}))

    try do
      {:ok, counts} =
        Repo.transaction(
          fn -> reconcile(records, present_ids, market, run.id, baseline?) end,
          timeout: :infinity
        )

      summary =
        counts
        |> Map.merge(meta)
        |> Map.merge(%{
          cloud_titles: length(records),
          duration_ms: System.monotonic_time(:millisecond) - started
        })

      finalize_run(run, "success", summary, started, nil)
      Logger.info("Gameglass ingest complete: #{inspect(summary)}")
      {:ok, summary}
    rescue
      e ->
        finalize_run(run, "failed", %{}, started, Exception.message(e))
        reraise e, __STACKTRACE__
    end
  end

  defp finalize_run(run, status, summary, started_mono, error) do
    attrs =
      %{
        status: status,
        finished_at: DateTime.utc_now() |> DateTime.truncate(:second),
        duration_ms: System.monotonic_time(:millisecond) - started_mono,
        error: error && inspect(error) |> String.slice(0, 500)
      }
      |> Map.merge(
        Map.take(summary, [
          :enumerated,
          :from_sigl,
          :from_subscriptions,
          :enriched,
          :cloud_titles,
          :added,
          :removed,
          :changed
        ])
      )

    run |> Run.changeset(attrs) |> Repo.update!()
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

  defp reconcile(records, present_ids, market, run_id, baseline?) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    existing = load_existing(market)

    events =
      Enum.flat_map(records, fn record ->
        upsert_record(record, existing[record.game.dedup_key], now, baseline?)
      end)

    removal_events = mark_removed(existing, records, present_ids, now)

    all_events = events ++ removal_events
    insert_events(all_events, now, run_id)

    %{
      added: count_kind(all_events, "game_added"),
      removed: count_kind(all_events, "game_removed"),
      changed:
        Enum.count(
          all_events,
          &(&1.kind in ~w(tier_status_changed price_changed))
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

  defp upsert_record(record, nil, now, baseline?) do
    # On the baseline run we don't know the true add date, so leave added_at nil
    # ("tracked since launch"); genuine later additions get dated.
    added_at = if baseline?, do: nil, else: now

    attrs =
      record.game
      |> Map.merge(%{
        first_seen_at: now,
        last_verified_at: now,
        last_changed_at: now,
        added_at: added_at,
        removed_at: nil
      })

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

  defp upsert_record(record, %Game{} = existing, now, _baseline?) do
    new = record.game

    status_events = tier_status_events(existing, record.tier_statuses, now)

    price_events =
      if existing.price_formatted != new.price_formatted do
        [event("price_changed", existing, existing.price_formatted, new.price_formatted)]
      else
        []
      end

    # Streamability transitions drive added_at / removed_at and their own events.
    {transition_events, date_attrs} =
      cond do
        not existing.streamable and new.streamable ->
          {[event("game_added", existing, nil, nil)], %{added_at: now, removed_at: nil}}

        existing.streamable and not new.streamable ->
          {[event("game_removed", existing, nil, nil)], %{removed_at: now}}

        true ->
          {[], %{}}
      end

    changed? = status_events != [] or price_events != [] or transition_events != []

    attrs =
      new
      |> Map.put(:last_verified_at, now)
      |> Map.merge(date_attrs)
      |> maybe_put_changed(changed?, now)

    existing
    |> Game.changeset(attrs)
    |> Repo.update!()

    upsert_product_link(record, existing, now)

    status_events ++ price_events ++ transition_events
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
      |> Repo.update_all(
        set: [streamable: false, last_changed_at: now, last_verified_at: now, removed_at: now]
      )

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

  defp event(kind, game, old, new) do
    %{
      kind: kind,
      game_id: game.id,
      xcloud_title_id: game.xcloud_title_id || game.dedup_key,
      old_value: old,
      new_value: new,
      detail: game.title
    }
  end

  defp insert_events([], _now, _run_id), do: :ok

  defp insert_events(events, now, run_id) do
    rows =
      Enum.map(events, fn e ->
        %{
          kind: e.kind,
          xcloud_title_id: Map.get(e, :xcloud_title_id),
          game_id: Map.get(e, :game_id),
          run_id: run_id,
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
