defmodule Gameglass.Scanner do
  @moduledoc """
  One full crawl of the anonymous public catalog, committed to the data dir:

    1. Enumerate the cloud catalog from the union of the "All games" SIGL and
       every subscription plan (the gallery SIGL alone omits ~35 cloud titles,
       e.g. EA Play games).
    2. Enrich each product (programs, pass metadata, price, XCloudTitleId).
    3. Keep cloud titles, dedupe by streamable unit, compute the tier matrix
       (`Snapshot.build/1`).
    4. Diff against the previous snapshot and write `data/*.json(l)`
       (`Store.commit/4`).

  Scheduling lives outside (CI cron / `mix gameglass.scan`); this module is a
  single function.
  """

  alias Gameglass.Catalog.{Client, Snapshot, Store}

  @doc """
  Runs a full scan into `opts[:data_dir]` (default `"data"`). Returns
  `{:ok, summary}` or `{:error, reason}`; either way the run is recorded in
  `runs.jsonl`.
  """
  @spec scan(keyword()) :: {:ok, map()} | {:error, term()}
  def scan(opts \\ []) do
    dir = Keyword.get(opts, :data_dir, "data")
    market = Client.market(opts)

    with {:ok, enumeration} <- Client.fetch_catalog_ids(opts),
         {:ok, raw} <- Client.fetch_products(enumeration.ids, opts) do
      scanned_games = Snapshot.build(raw, market: market)

      meta = %{
        enumerated: length(enumeration.ids),
        from_sigl: enumeration.sigl,
        from_subscriptions: enumeration.subscriptions,
        enriched: map_size(raw)
      }

      commit_opts = opts |> Keyword.put(:market, market) |> Keyword.put(:meta, meta)
      Store.commit(dir, scanned_games, MapSet.new(enumeration.ids), commit_opts)
    else
      {:error, reason} ->
        Store.record_failure(dir, inspect(reason))
        {:error, reason}
    end
  end
end
