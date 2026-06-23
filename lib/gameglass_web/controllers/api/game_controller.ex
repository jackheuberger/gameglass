defmodule GameglassWeb.API.GameController do
  @moduledoc """
  Public, read-only verify API. Gameglass acts as an external source of truth
  for whether a title is configured as streamable on Xbox Cloud Gaming and which
  subscription tiers can stream it.

  Endpoints:

    * `GET /api/games/:product_id` - resolve a store productId/BigId (base game,
      edition, or bundle) to the streamable game(s) it grants.
    * `GET /api/games?xcloudTitleId=TUNIC` - resolve by XCloudTitleId.
    * `GET /api/games?xboxTitleId=1848191014` - resolve by xboxTitleId.
  """
  use GameglassWeb, :controller

  alias Gameglass.Catalog
  alias Gameglass.Catalog.{Links, Tiers}

  def show(conn, %{"product_id" => product_id}) do
    product_id
    |> then(&Catalog.resolve(:product_id, &1))
    |> respond(conn)
  end

  def index(conn, %{"xcloudTitleId" => id}),
    do: respond(Catalog.resolve(:xcloud_title_id, id), conn)

  def index(conn, %{"xboxTitleId" => id}), do: respond(Catalog.resolve(:xbox_title_id, id), conn)

  def index(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "missing_query", message: "Provide xcloudTitleId or xboxTitleId."})
  end

  defp respond([], conn) do
    conn
    |> put_status(:not_found)
    |> json(%{error: "not_found", streamable: false, count: 0, games: []})
  end

  defp respond(games, conn) do
    payload = %{
      streamable: Enum.any?(games, & &1.streamable),
      count: length(games),
      games: Enum.map(games, &game_json/1)
    }

    json(conn, payload)
  end

  defp game_json(game) do
    statuses = Catalog.status_map(game)

    %{
      xcloud_title_id: game.xcloud_title_id,
      product_id: game.base_product_id,
      title: game.title,
      streamable: game.streamable,
      is_free: game.is_free,
      tiers: Map.new(Tiers.keys(), &{&1, Map.get(statuses, &1, "unknown")}),
      price: price_json(game),
      links: Links.all(game.base_product_id, game.title),
      last_verified_at: game.last_verified_at
    }
  end

  defp price_json(%{price_formatted: nil}), do: nil

  defp price_json(game) do
    %{value: game.price_value, formatted: game.price_formatted, currency: game.price_currency}
  end
end
