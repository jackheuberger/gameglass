defmodule Gameglass.Catalog.ResolveTest do
  use ExUnit.Case, async: true

  alias Gameglass.Catalog.Resolve
  alias Gameglass.Catalog.Types.Game

  defp game(overrides) do
    struct!(
      Game,
      Map.merge(
        %{
          id: "TUNIC",
          xcloud_title_id: "TUNIC",
          market: "US",
          title: "TUNIC",
          base_product_id: "9NLRT31Z4RWM",
          product_ids: ["9NLRT31Z4RWM"],
          xbox_title_id: 1_848_191_014,
          streamable: true,
          is_free: false,
          programs: [],
          tiers: %{},
          first_seen_at: "2026-01-01T00:00:00Z",
          last_changed_at: "2026-01-01T00:00:00Z"
        },
        overrides
      )
    )
  end

  test "resolves by base product id, xcloud title id, and xbox title id" do
    indexes = Resolve.build([game(%{})])

    assert [%{title: "TUNIC"}] = Resolve.lookup(indexes, :product_id, "9NLRT31Z4RWM")
    assert [%{title: "TUNIC"}] = Resolve.lookup(indexes, :xcloud_title_id, "TUNIC")
    assert [%{title: "TUNIC"}] = Resolve.lookup(indexes, :xbox_title_id, 1_848_191_014)
    assert [%{title: "TUNIC"}] = Resolve.lookup(indexes, :xbox_title_id, "1848191014")
  end

  test "unknown identifiers resolve to an empty list" do
    indexes = Resolve.build([game(%{})])

    assert Resolve.lookup(indexes, :product_id, "NOPE") == []
    assert Resolve.lookup(indexes, :xcloud_title_id, "NOPE") == []
    assert Resolve.lookup(indexes, :xbox_title_id, "0") == []
  end

  test "extra product ids (editions/bundles) resolve to their games" do
    ori1 = game(%{id: "ORI1", xcloud_title_id: "ORI1", base_product_id: "A"})

    ori2 =
      game(%{
        id: "ORI2",
        xcloud_title_id: "ORI2",
        base_product_id: "B",
        # the collection bundle grants this game too
        product_ids: ["B", "BUNDLE"]
      })

    indexes = Resolve.build([%{ori1 | product_ids: ["A", "BUNDLE"]}, ori2])

    assert [%{id: "ORI1"}, %{id: "ORI2"}] =
             Resolve.lookup(indexes, :product_id, "BUNDLE")
  end

  test "games without an xcloud or xbox title id are skipped in those indexes" do
    indexes =
      Resolve.build([game(%{xcloud_title_id: nil, xbox_title_id: nil})])

    assert indexes.by_xcloud == %{}
    assert indexes.by_xbox == %{}
    assert map_size(indexes.by_product) == 1
  end
end
