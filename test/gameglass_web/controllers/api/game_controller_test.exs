defmodule GameglassWeb.API.GameControllerTest do
  use GameglassWeb.ConnCase, async: true

  alias Gameglass.Repo
  alias Gameglass.Catalog.{Game, TierStatus, Product, Entitlement}

  defp seed_game(attrs) do
    {:ok, game} =
      %Game{}
      |> Game.changeset(
        Map.merge(
          %{
            dedup_key: attrs[:xcloud_title_id] || attrs[:base_product_id],
            market: "US",
            streamable: true,
            last_verified_at: DateTime.utc_now() |> DateTime.truncate(:second)
          },
          attrs
        )
      )
      |> Repo.insert()

    Enum.each(attrs[:tiers] || %{}, fn {tier, status} ->
      Repo.insert!(
        TierStatus.changeset(%TierStatus{}, %{game_id: game.id, tier_key: tier, status: status})
      )
    end)

    game
  end

  setup do
    game =
      seed_game(%{
        xcloud_title_id: "CYBERPUNK2077",
        base_product_id: "BX3M8L83BBRW",
        title: "Cyberpunk 2077",
        xbox_title_id: 123_456,
        price_value: 59.99,
        price_formatted: "$59.99",
        price_currency: "USD",
        tiers: %{
          "starter" => "unknown",
          "essential" => "purchase",
          "premium" => "included",
          "ultimate" => "included"
        }
      })

    %{game: game}
  end

  test "GET /api/games/:product_id resolves by BigId", %{conn: conn} do
    conn = get(conn, ~p"/api/games/BX3M8L83BBRW")
    body = json_response(conn, 200)

    assert body["streamable"] == true
    assert body["count"] == 1
    assert [g] = body["games"]
    assert g["xcloud_title_id"] == "CYBERPUNK2077"
    assert g["tiers"]["essential"] == "purchase"
    assert g["tiers"]["premium"] == "included"
    assert g["price"]["formatted"] == "$59.99"
    assert g["links"]["store"] =~ "/games/store/"
    assert g["links"]["play_new"] =~ "play.xbox.com/products/BX3M8L83BBRW"
    assert g["links"]["play_legacy"] =~ "xbox.com/play/games/"
  end

  test "GET /api/games?xcloudTitleId= resolves by XCloudTitleId", %{conn: conn} do
    conn = get(conn, ~p"/api/games?xcloudTitleId=CYBERPUNK2077")
    body = json_response(conn, 200)
    assert [%{"title" => "Cyberpunk 2077"}] = body["games"]
  end

  test "GET /api/games?xboxTitleId= resolves by xboxTitleId", %{conn: conn} do
    conn = get(conn, ~p"/api/games?xboxTitleId=123456")
    assert [%{"xcloud_title_id" => "CYBERPUNK2077"}] = json_response(conn, 200)["games"]
  end

  test "unknown product id returns 404", %{conn: conn} do
    conn = get(conn, ~p"/api/games/NOPE")
    body = json_response(conn, 404)
    assert body["error"] == "not_found"
    assert body["streamable"] == false
  end

  test "missing query returns 400", %{conn: conn} do
    conn = get(conn, ~p"/api/games")
    assert json_response(conn, 400)["error"] == "missing_query"
  end

  test "resolves a bundle product to its constituent games", %{conn: conn} do
    g1 =
      seed_game(%{
        xcloud_title_id: "ORIBLINDFORESTDE",
        base_product_id: "BW85KQB8Q31M",
        title: "Ori and the Blind Forest"
      })

    g2 =
      seed_game(%{
        xcloud_title_id: "ORIANDTHEWILLOFTHEWISPS",
        base_product_id: "9N8CD0XZKLP4",
        title: "Ori and the Will of the Wisps"
      })

    {:ok, bundle} =
      %Product{}
      |> Product.changeset(%{product_id: "9P5MBBFF3RNT", market: "US", kind: "bundle"})
      |> Repo.insert()

    for g <- [g1, g2] do
      Repo.insert!(
        Entitlement.changeset(%Entitlement{}, %{product_ref: bundle.id, game_id: g.id})
      )
    end

    body = conn |> get(~p"/api/games/9P5MBBFF3RNT") |> json_response(200)
    assert body["count"] == 2
    titles = body["games"] |> Enum.map(& &1["xcloud_title_id"]) |> Enum.sort()
    assert titles == ["ORIANDTHEWILLOFTHEWISPS", "ORIBLINDFORESTDE"]
  end
end
