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

  test "baseline games show 'since launch' instead of a fake add date", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "since launch"
  end

  test "recently-added games show a New badge", %{conn: conn} do
    seed_game(%{
      xcloud_title_id: "ABYSSUS",
      base_product_id: "ABYSSUSID",
      title: "Abyssus",
      publisher: "The Arcade Crew",
      added_at: DateTime.utc_now() |> DateTime.truncate(:second),
      tiers: %{"ultimate" => "included"}
    })

    {:ok, _view, html} = live(conn, ~p"/?recently_added=true")

    assert html =~ "The Arcade Crew"
    assert html =~ "New"
    refute html =~ "Finji"
  end

  test "'Show removed' toggle lists removed games with a removal date", %{conn: conn} do
    seed_game(%{
      xcloud_title_id: "SOJOURNER",
      base_product_id: "SOJOURNERID",
      title: "Signs of the Sojourner",
      publisher: "Echodog Games",
      streamable: false,
      removed_at: DateTime.utc_now() |> DateTime.truncate(:second),
      tiers: %{"ultimate" => "included"}
    })

    # Default view hides removed games.
    {:ok, view, html} = live(conn, ~p"/")
    refute html =~ "Echodog Games"

    # Removed view shows them.
    {:ok, _view, removed_html} = live(conn, ~p"/?removed=true")
    assert removed_html =~ "Echodog Games"
    assert removed_html =~ "Removed"
    refute removed_html =~ "Finji"

    # The toggle button advertises the removed count.
    assert render(view) =~ "Show removed (1)"
  end
end
