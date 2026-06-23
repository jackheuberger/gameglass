defmodule Gameglass.Catalog do
  @moduledoc """
  Read API over the ingested catalog: query games for the comparison matrix,
  resolve products/games for the verify API, and surface recent changes.
  """

  import Ecto.Query

  alias Gameglass.Repo
  alias Gameglass.Catalog.{Game, TierStatus, Product, Entitlement, ChangeEvent, Tiers}

  @default_per_page 50
  @stream_statuses ~w(free included purchase)

  @doc "Tier configuration (for column headers etc.)."
  def tiers, do: Tiers.all()

  @doc """
  Lists games for the comparison matrix with filtering, sorting and pagination.

  Options:

    * `:page`, `:per_page`
    * `:search`            - case-insensitive title substring
    * `:streamable_on`     - tier key; keep games streamable (included/purchase/free) on it
    * `:purchase_on`       - tier key; keep games that require purchase on it
    * `:f2p_only`          - boolean; only free-to-play titles
    * `:recently_changed`  - boolean; only games changed in the last 14 days, newest first
    * `:include_unstreamable` - boolean; include games no longer in the cloud catalog
    * `:sort`              - `:recent` (default) | `:title` | `:price`
  """
  def list_games(opts \\ []) do
    page = max(opts[:page] || 1, 1)
    per_page = opts[:per_page] || @default_per_page

    query =
      from(g in Game, as: :game)
      |> filter_streamable(opts)
      |> filter_search(opts[:search])
      |> filter_f2p(opts[:f2p_only])
      |> filter_tier(:streamable_on, opts[:streamable_on], @stream_statuses)
      |> filter_tier(:purchase_on, opts[:purchase_on], ["purchase"])
      |> filter_recently_changed(opts[:recently_changed])

    total = Repo.aggregate(query, :count, :id)

    games =
      query
      |> order_games(opts[:sort], opts[:recently_changed])
      |> limit(^per_page)
      |> offset(^((page - 1) * per_page))
      |> preload(:tier_statuses)
      |> Repo.all()

    %{
      games: games,
      total: total,
      page: page,
      per_page: per_page,
      total_pages: max(ceil(total / per_page), 1)
    }
  end

  defp filter_streamable(query, opts) do
    if opts[:include_unstreamable] do
      query
    else
      where(query, [g], g.streamable == true)
    end
  end

  defp filter_search(query, nil), do: query
  defp filter_search(query, ""), do: query

  defp filter_search(query, search) do
    like = "%#{String.replace(search, "%", "\\%")}%"
    where(query, [g], like(g.title, ^like))
  end

  defp filter_f2p(query, true), do: where(query, [g], g.is_free == true)
  defp filter_f2p(query, _), do: query

  defp filter_tier(query, _opt, nil, _statuses), do: query
  defp filter_tier(query, _opt, "", _statuses), do: query

  defp filter_tier(query, _opt, tier_key, statuses) do
    sub =
      from(t in TierStatus,
        where:
          t.game_id == parent_as(:game).id and t.tier_key == ^tier_key and t.status in ^statuses
      )

    where(query, exists(sub))
  end

  defp filter_recently_changed(query, true) do
    since = DateTime.utc_now() |> DateTime.add(-14, :day)
    where(query, [g], g.last_changed_at >= ^since)
  end

  defp filter_recently_changed(query, _), do: query

  defp order_games(query, _sort, true), do: order_by(query, [g], desc: g.last_changed_at)
  defp order_games(query, :title, _), do: order_by(query, [g], asc: g.title)

  defp order_games(query, :price, _),
    do: order_by(query, [g], asc_nulls_last: g.price_value, asc: g.title)

  defp order_games(query, _default, _),
    do: order_by(query, [g], desc: g.first_seen_at, asc: g.title)

  @spec recent_changes() :: any()
  @doc "Most recent change events, newest first."
  def recent_changes(limit \\ 50) do
    ChangeEvent
    |> order_by([e], desc: e.occurred_at, desc: e.id)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "High-level counts for the dashboard header."
  def stats do
    %{
      games: Repo.aggregate(from(g in Game, where: g.streamable), :count, :id),
      free: Repo.aggregate(from(g in Game, where: g.is_free and g.streamable), :count, :id),
      last_verified: Repo.one(from(g in Game, select: max(g.last_verified_at)))
    }
  end

  @doc "Converts a game's tier_statuses association into a `%{tier_key => status}` map."
  def status_map(%Game{tier_statuses: statuses}) when is_list(statuses) do
    Map.new(statuses, &{&1.tier_key, &1.status})
  end

  def status_map(_), do: %{}

  # --- verify API ------------------------------------------------------------

  @doc """
  Resolves an identifier to the streamable game(s) it grants. Accepts one of
  `:product_id`, `:xcloud_title_id`, or `:xbox_title_id`. Returns a (possibly
  empty) list of games with tier statuses preloaded.
  """
  def resolve(:xcloud_title_id, value) do
    Game
    |> where([g], g.xcloud_title_id == ^value)
    |> preload(:tier_statuses)
    |> Repo.all()
  end

  def resolve(:xbox_title_id, value) when is_integer(value) do
    Game
    |> where([g], g.xbox_title_id == ^value)
    |> preload(:tier_statuses)
    |> Repo.all()
  end

  def resolve(:xbox_title_id, value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} -> resolve(:xbox_title_id, n)
      :error -> []
    end
  end

  def resolve(:product_id, value) do
    # Direct hit: a game whose base product is this id.
    direct =
      Game
      |> where([g], g.base_product_id == ^value)
      |> preload(:tier_statuses)
      |> Repo.all()

    case direct do
      [] -> resolve_via_product(value)
      games -> games
    end
  end

  # A product row (e.g. an edition/bundle) linked to game(s) via entitlements.
  defp resolve_via_product(product_id) do
    Game
    |> join(:inner, [g], e in Entitlement, on: e.game_id == g.id)
    |> join(:inner, [g, e], p in Product, on: p.id == e.product_ref)
    |> where([g, e, p], p.product_id == ^product_id)
    |> preload(:tier_statuses)
    |> Repo.all()
  end
end
