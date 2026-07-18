defmodule Gameglass.Catalog.SnapshotTest do
  use ExUnit.Case, async: true

  alias Gameglass.Catalog.{Mapper, Snapshot}
  alias Gameglass.Catalog.Types.RawProduct

  # A standalone game with no shared editions passes through unchanged.
  defp record(product_id, xcloud_title_id, programs, subscription_product_ids, price \\ nil) do
    product_id
    |> raw(xcloud_title_id, programs, subscription_product_ids, price)
    |> Mapper.normalize()
  end

  defp raw(product_id, xcloud_title_id, programs, subscription_product_ids, price \\ nil) do
    payload = %{
      "ProductTitle" => product_id,
      "XCloudTitleId" => xcloud_title_id,
      "XCloudOfferings" => %{"CLOUDGAMING" => %{"Programs" => programs}},
      "PassMetadataByPassProductId" => Map.new(subscription_product_ids, &{&1, %{}}),
      "AnonymousPrice" => %{"MSRP" => %{"value" => price, "formattedValue" => "x"}}
    }

    RawProduct.from_json(product_id, payload)
  end

  @programs ~w(GPULTIMATE CALLISTO DIA EUROPA TRITON)
  @premium "CFQ7TTC0P85B"
  @console "CFQ7TTC0K6L8"

  test "merges editions sharing an XCloudTitleId, taking the best entitlement" do
    # Mirrors Forza Horizon 5: Premium/Deluxe editions carry no pass metadata,
    # the Standard edition is included on Premium/Ultimate.
    scanned_games = [
      record("PREMIUM_ED", "FORZAHORIZON5", @programs, [], 99.99),
      record("DELUXE_ED", "FORZAHORIZON5", @programs, [], 79.99),
      record("STANDARD_ED", "FORZAHORIZON5", @programs, [@console, @premium], 59.99)
    ]

    assert [merged] = Snapshot.merge_editions(scanned_games)

    # Representative is the standard edition (richest pass, lowest price).
    assert merged.base_product_id == "STANDARD_ED"
    assert merged.price_value == 59.99

    s = merged.tiers
    assert s["premium"] == :included
    assert s["ultimate"] == :included
    assert s["essential"] == :purchase
  end

  test "leaves a singleton record untouched" do
    [rec] = [record("ONLY", "SOLO", @programs, [@premium], 19.99)]
    assert [^rec] = Snapshot.merge_editions([rec])
  end

  test "distinct streamable units are kept separate" do
    scanned_games = [
      record("A", "GAME_A", @programs, [@premium]),
      record("B", "GAME_B", @programs, [])
    ]

    assert length(Snapshot.merge_editions(scanned_games)) == 2
  end

  test "build normalizes raw products and drops non-cloud titles" do
    raw_products = %{
      "A" => raw("A", "GAME_A", @programs, [@premium]),
      # An edition/bundle wrapper: no CLOUDGAMING offering.
      "WRAPPER" =>
        RawProduct.from_json("WRAPPER", %{
          "ProductTitle" => "Wrapper",
          "XCloudOfferings" => %{}
        })
    }

    assert [rec] = Snapshot.build(raw_products)
    assert rec.id == "GAME_A"
  end
end
