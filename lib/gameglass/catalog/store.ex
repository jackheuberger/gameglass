defmodule Gameglass.Catalog.Store do
  @moduledoc """
  File-backed catalog state. The "database" is a set of committed JSON files:

    * `games.json`    - the full current snapshot, one entry per streamable unit
    * `changes.jsonl` - append-only change events (game added/removed, tier
      status change, price change), one JSON object per line
    * `runs.jsonl`    - append-only scan audit log, one JSON object per line

  `commit/4` reconciles a freshly scanned snapshot against the previous
  `games.json` — with the same semantics the Ecto pipeline had: the first
  successful run is the baseline (`added_at: nil`, "tracked since launch"),
  later appearances get a genuine `added_at`, disappearances get `removed_at`
  and are kept (muted) so they re-surface honestly if they return.

  Because the files live in git, `git log -p data/games.json` is the full audit
  trail; the JSONL files make the same history queryable without walking git.
  To keep that trail readable, games carry no per-scan timestamps: a no-change
  scan touches only the top-level `generated_at` (which is also when every
  present entry was last verified — the site derives `last_verified_at` from it).

  On disk everything is plain JSON; in memory it uses the structs under
  `Gameglass.Catalog.Types`, decoded and encoded at the file boundary.
  """

  require Logger

  alias Gameglass.Catalog.Types.{Event, Game, Run, ScannedGame, StoredSnapshot}

  @doc "Path of the snapshot file within a data dir."
  @spec games_path(String.t()) :: String.t()
  def games_path(dir), do: Path.join(dir, "games.json")

  @doc "Path of the change-event log within a data dir."
  @spec changes_path(String.t()) :: String.t()
  def changes_path(dir), do: Path.join(dir, "changes.jsonl")

  @doc "Path of the run log within a data dir."
  @spec runs_path(String.t()) :: String.t()
  def runs_path(dir), do: Path.join(dir, "runs.jsonl")

  @doc "Loads the full snapshot document (`generated_at`, `market`, `games`, …), or nil."
  @spec load_snapshot(String.t()) :: StoredSnapshot.t() | nil
  def load_snapshot(dir) do
    case File.read(games_path(dir)) do
      {:ok, body} -> body |> Jason.decode!() |> StoredSnapshot.from_json()
      {:error, :enoent} -> nil
    end
  end

  @doc "Loads the persisted games, or `[]`."
  @spec load_games(String.t()) :: [Game.t()]
  def load_games(dir) do
    case load_snapshot(dir) do
      nil -> []
      doc -> doc.games
    end
  end

  @doc "Loads all recorded runs, oldest first, or `[]`."
  @spec load_runs(String.t()) :: [Run.t()]
  def load_runs(dir), do: load_jsonl(runs_path(dir), &Run.from_json/1)

  @doc "Loads all recorded change events, oldest first, or `[]`."
  @spec load_changes(String.t()) :: [Event.t()]
  def load_changes(dir), do: load_jsonl(changes_path(dir), &Event.from_json/1)

  @doc "The most recent finished run, or nil."
  @spec last_run(String.t()) :: Run.t() | nil
  def last_run(dir), do: dir |> load_runs() |> List.last()

  defp load_jsonl(path, from_json) do
    case File.read(path) do
      {:ok, body} ->
        body
        |> String.split("\n", trim: true)
        |> Enum.map(fn line -> line |> Jason.decode!() |> from_json.() end)

      {:error, :enoent} ->
        []
    end
  end

  @doc """
  Reconciles scanned games into the data dir within a recorded run.

  `scanned_games` are `Catalog.Snapshot.build/1` outputs;
  `enumerated_product_ids` is the set of product ids seen this crawl and is
  used to detect removals. `opts` may carry `:market` and a `:meta` map of
  enumeration counts. Returns `{:ok, summary}`; a failing reconcile records a
  failed run line and reraises.
  """
  @spec commit(String.t(), [ScannedGame.t()], MapSet.t(String.t()), keyword()) ::
          {:ok, map()}
  def commit(dir, scanned_games, enumerated_product_ids, opts \\ []) do
    market = Keyword.get(opts, :market, "US")
    meta = Keyword.get(opts, :meta, %{})
    started = System.monotonic_time(:millisecond)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    runs = load_runs(dir)
    baseline? = not Enum.any?(runs, &(&1.status == :success))
    run_id = next_run_id(runs)

    try do
      %{games: games, events: events, counts: counts} =
        reconcile(load_games(dir), scanned_games, enumerated_product_ids, now, baseline?)

      summary =
        counts
        |> Map.merge(meta)
        |> Map.merge(%{
          cloud_titles: length(scanned_games),
          duration_ms: System.monotonic_time(:millisecond) - started
        })

      File.mkdir_p!(dir)
      write_games(dir, games, market, now)
      append_events(dir, events, run_id)
      append_run(dir, run_line(run_id, :success, now, started, summary, nil))

      Logger.info("Gameglass scan committed: #{inspect(summary)}")
      {:ok, summary}
    rescue
      e ->
        record_failure(dir, run_id, now, started, Exception.message(e))
        reraise e, __STACKTRACE__
    end
  end

  @doc """
  Appends a failed-run line, e.g. when enumeration/enrichment fails before
  there is anything to reconcile.
  """
  @spec record_failure(
          String.t(),
          pos_integer() | nil,
          DateTime.t() | nil,
          integer() | nil,
          String.t()
        ) :: :ok
  def record_failure(dir, run_id \\ nil, started_at \\ nil, started_mono \\ nil, error) do
    started_at = started_at || DateTime.utc_now() |> DateTime.truncate(:second)
    started_mono = started_mono || System.monotonic_time(:millisecond)
    run_id = run_id || next_run_id(load_runs(dir))

    File.mkdir_p!(dir)
    append_run(dir, run_line(run_id, :failed, started_at, started_mono, %{}, error))
    :ok
  end

  @doc """
  Pure reconciliation of scanned games against the previous snapshot.

  Returns `%{games: games, events: events, counts: %{added, removed,
  changed}}`. Games are sorted by id for stable diffs.
  """
  @spec reconcile(
          [Game.t()],
          [ScannedGame.t()],
          MapSet.t(String.t()),
          DateTime.t(),
          boolean()
        ) :: %{games: [Game.t()], events: [Event.t()], counts: map()}
  def reconcile(previous_games, scanned_games, enumerated_product_ids, now, baseline?) do
    previous_by_id = Map.new(previous_games, &{&1.id, &1})

    {reconciled_games, event_groups} =
      Enum.map_reduce(scanned_games, [], fn scanned_game, groups ->
        {game, game_events} =
          case previous_by_id[scanned_game.id] do
            nil -> new_game(scanned_game, now, baseline?)
            previous_game -> merge_game(previous_game, scanned_game, now)
          end

        {game, [game_events | groups]}
      end)

    events = event_groups |> Enum.reverse() |> Enum.concat()
    current_game_ids = MapSet.new(scanned_games, & &1.id)

    {removed_games, removal_events} =
      mark_removed(previous_games, current_game_ids, enumerated_product_ids, now)

    removed_game_ids = MapSet.new(removed_games, & &1.id)

    unchanged_games =
      Enum.reject(previous_games, fn game ->
        MapSet.member?(current_game_ids, game.id) or
          MapSet.member?(removed_game_ids, game.id)
      end)

    all_events = events ++ removal_events

    games =
      (reconciled_games ++ removed_games ++ unchanged_games)
      |> Enum.sort_by(& &1.id)

    %{
      games: games,
      events: all_events,
      counts: %{
        added: count_kind(all_events, :game_added),
        removed: count_kind(all_events, :game_removed),
        changed: Enum.count(all_events, &(&1.kind in [:tier_status_changed, :price_changed]))
      }
    }
  end

  # --- new-game path ---------------------------------------------------------

  defp new_game(scanned_game, now, baseline?) do
    # On the baseline run we don't know the true add date, so leave added_at nil
    # ("tracked since launch"); genuine later additions get dated.
    attrs =
      scanned_game
      |> persisted_fields()
      |> Map.merge(%{
        first_seen_at: iso(now),
        last_changed_at: iso(now),
        added_at: if(baseline?, do: nil, else: iso(now)),
        removed_at: nil,
        product_ids: [scanned_game.base_product_id]
      })

    game = struct!(Game, attrs)

    {game, [event(:game_added, game, now)]}
  end

  # --- update path -------------------------------------------------------------

  defp merge_game(previous, scanned_game, now) do
    status_events = tier_status_events(previous, scanned_game.tiers, now)

    price_events =
      if previous.price_formatted != scanned_game.price_formatted do
        [
          event(:price_changed, previous, now,
            old_value: previous.price_formatted,
            new_value: scanned_game.price_formatted
          )
        ]
      else
        []
      end

    # Streamability transitions drive added_at / removed_at and their own events.
    {transition_events, date_attrs} =
      cond do
        not previous.streamable and scanned_game.streamable ->
          {[event(:game_added, previous, now)], %{added_at: iso(now), removed_at: nil}}

        previous.streamable and not scanned_game.streamable ->
          {[event(:game_removed, previous, now)], %{removed_at: iso(now)}}

        true ->
          {[], %{}}
      end

    all_events = status_events ++ price_events ++ transition_events
    changed? = all_events != []

    attrs =
      scanned_game
      |> persisted_fields()
      |> Map.merge(%{
        first_seen_at: previous.first_seen_at,
        added_at: previous.added_at,
        removed_at: previous.removed_at,
        last_changed_at: if(changed?, do: iso(now), else: previous.last_changed_at),
        product_ids: Enum.uniq(previous.product_ids ++ [scanned_game.base_product_id])
      })
      |> Map.merge(date_attrs)

    game = struct!(Game, attrs)

    {game, all_events}
  end

  defp tier_status_events(previous, new_tiers, now) do
    Enum.flat_map(new_tiers, fn {tier_key, status} ->
      case previous.tiers[tier_key] do
        # A tier we haven't recorded before is adopted silently, not a change.
        nil ->
          []

        ^status ->
          []

        old ->
          [
            event(:tier_status_changed, previous, now,
              tier_key: tier_key,
              old_value: old,
              new_value: status
            )
          ]
      end
    end)
  end

  # --- removal path ------------------------------------------------------------

  defp mark_removed(previous_games, current_game_ids, enumerated_product_ids, now) do
    previous_games
    |> Enum.filter(fn game ->
      game.streamable and not MapSet.member?(current_game_ids, game.id) and
        not MapSet.member?(enumerated_product_ids, game.base_product_id)
    end)
    |> Enum.map(fn previous_game ->
      removed_game = %{
        previous_game
        | streamable: false,
          removed_at: iso(now),
          last_changed_at: iso(now)
      }

      {removed_game, event(:game_removed, previous_game, now)}
    end)
    |> Enum.unzip()
  end

  # --- persisted game / event shapes ------------------------------------------

  defp persisted_fields(scanned_game) do
    scanned_game
    |> Map.from_struct()
    |> Map.delete(:subscription_product_ids)
  end

  defp event(kind, game, now, extra \\ []) do
    %Event{
      kind: kind,
      game_id: game.id,
      xcloud_title_id: game.xcloud_title_id || game.id,
      tier_key: Keyword.get(extra, :tier_key),
      old_value: Keyword.get(extra, :old_value),
      new_value: Keyword.get(extra, :new_value),
      detail: game.title,
      occurred_at: iso(now)
    }
  end

  defp count_kind(events, kind), do: Enum.count(events, &(&1.kind == kind))

  # --- file writes ---------------------------------------------------------------

  defp write_games(dir, games, market, now) do
    doc = %StoredSnapshot{
      generated_at: iso(now),
      market: market,
      count: length(games),
      games: games
    }

    File.write!(games_path(dir), [Jason.encode_to_iodata!(doc, pretty: true), "\n"])
  end

  defp append_events(_dir, [], _run_id), do: :ok

  defp append_events(dir, events, run_id) do
    lines =
      Enum.map(events, fn e ->
        [e |> Map.put(:run_id, run_id) |> Jason.encode_to_iodata!(), "\n"]
      end)

    File.write!(changes_path(dir), lines, [:append])
  end

  defp append_run(dir, line) do
    File.write!(runs_path(dir), [Jason.encode_to_iodata!(line), "\n"], [:append])
  end

  defp next_run_id([]), do: 1
  defp next_run_id(runs), do: Enum.max(Enum.map(runs, & &1.id)) + 1

  defp run_line(run_id, status, started_at, started_mono, summary, error) do
    %Run{
      id: run_id,
      started_at: iso(started_at),
      finished_at: iso(DateTime.utc_now() |> DateTime.truncate(:second)),
      status: status,
      enumerated: summary[:enumerated],
      from_sigl: summary[:from_sigl],
      from_subscriptions: summary[:from_subscriptions],
      enriched: summary[:enriched],
      cloud_titles: summary[:cloud_titles],
      added: summary[:added],
      removed: summary[:removed],
      changed: summary[:changed],
      duration_ms: System.monotonic_time(:millisecond) - started_mono,
      error: error && String.slice(error, 0, 500)
    }
  end

  defp iso(nil), do: nil
  defp iso(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
end
