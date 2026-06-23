defmodule GameglassWeb.GamesLiveTest do
  use GameglassWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Gameglass.Repo
  alias Gameglass.Catalog.{Game, TierStatus}

  defp seed_game(attrs) do
    {:ok, game} =
      %Game{}
      |> Game.changeset(
        Map.merge(
          %{
            dedup_key: attrs[:xcloud_title_id] || attrs[:base_product_id],
            market: "US",
            streamable: true,
            first_seen_at: DateTime.utc_now() |> DateTime.truncate(:second),
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
    seed_game(%{
      xcloud_title_id: "TUNIC",
      base_product_id: "9NLRT31Z4RWM",
      title: "TUNIC",
      publisher: "Finji",
      tiers: %{
        "starter" => "included",
        "essential" => "included",
        "premium" => "included",
        "ultimate" => "included"
      }
    })

    seed_game(%{
      xcloud_title_id: "CYBERPUNK2077",
      base_product_id: "BX3M8L83BBRW",
      title: "Cyberpunk 2077",
      publisher: "CD PROJEKT RED",
      tiers: %{
        "starter" => "unknown",
        "essential" => "purchase",
        "premium" => "included",
        "ultimate" => "included"
      }
    })

    :ok
  end

  test "renders the matrix with tier columns and games", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Xbox Cloud Gaming streamability"
    assert html =~ "Finji"
    assert html =~ "CD PROJEKT RED"
    assert html =~ "Essential"
    assert html =~ "Ultimate"
  end

  test "title search filters the table", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    html =
      view
      |> form("#filters", filters: %{search: "tunic"})
      |> render_change()

    assert html =~ "Finji"
    refute html =~ "CD PROJEKT RED"
  end

  test "purchase-on-tier filter narrows results", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    html =
      view
      |> form("#filters", filters: %{purchase_on: "essential"})
      |> render_change()

    # Cyberpunk is purchase-required on Essential; Tunic is included.
    assert html =~ "CD PROJEKT RED"
    refute html =~ "Finji"
  end

  test "stats header reflects seeded game count", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "streamable games"
    assert html =~ "2"
  end
end
