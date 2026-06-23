defmodule Gameglass.IngestTest do
  use ExUnit.Case, async: true

  alias Gameglass.Ingest
  alias Gameglass.Catalog.Mapper

  # A standalone game with no shared editions passes through unchanged.
  defp record(product_id, xcloud_title_id, programs, pass_ids, price \\ nil) do
    raw = %{
      "ProductTitle" => product_id,
      "XCloudTitleId" => xcloud_title_id,
      "XCloudOfferings" => %{"CLOUDGAMING" => %{"Programs" => programs}},
      "PassMetadataByPassProductId" => Map.new(pass_ids, &{&1, %{}}),
      "AnonymousPrice" => %{"MSRP" => %{"value" => price, "formattedValue" => "x"}}
    }

    Mapper.normalize(product_id, raw)
  end

  defp statuses(rec), do: Map.new(rec.tier_statuses, &{&1.tier_key, &1.status})

  @programs ~w(GPULTIMATE CALLISTO DIA EUROPA TRITON)
  @premium "CFQ7TTC0P85B"
  @console "CFQ7TTC0K6L8"

  test "merges editions sharing an XCloudTitleId, taking the best entitlement" do
    # Mirrors Forza Horizon 5: Premium/Deluxe editions carry no pass metadata,
    # the Standard edition is included on Premium/Ultimate.
    records = [
      record("PREMIUM_ED", "FORZAHORIZON5", @programs, [], 99.99),
      record("DELUXE_ED", "FORZAHORIZON5", @programs, [], 79.99),
      record("STANDARD_ED", "FORZAHORIZON5", @programs, [@console, @premium], 59.99)
    ]

    assert [merged] = Ingest.dedupe_by_key(records)

    # Representative is the standard edition (richest pass, lowest price).
    assert merged.game.base_product_id == "STANDARD_ED"
    assert merged.game.price_value == 59.99

    s = statuses(merged)
    assert s["premium"] == "included"
    assert s["ultimate"] == "included"
    assert s["essential"] == "purchase"
  end

  test "leaves a singleton record untouched" do
    [rec] = [record("ONLY", "SOLO", @programs, [@premium], 19.99)]
    assert [^rec] = Ingest.dedupe_by_key([rec])
  end

  test "distinct streamable units are kept separate" do
    records = [
      record("A", "GAME_A", @programs, [@premium]),
      record("B", "GAME_B", @programs, [])
    ]

    assert length(Ingest.dedupe_by_key(records)) == 2
  end
end
