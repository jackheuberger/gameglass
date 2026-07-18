defmodule Gameglass.Catalog.ClassifierTest do
  use ExUnit.Case, async: true

  alias Gameglass.Catalog.Classifier

  # Pass SKUs (verified via displaycatalog)
  @essential "CFQ7TTC0K5DJ"
  @premium "CFQ7TTC0P85B"
  @starter "CFQ7TTC10QFD"
  @ea_play "CFQ7TTC0K5DH"
  @console "CFQ7TTC0K6L8"

  @standard_programs ~w(GPULTIMATE CALLISTO DIA EUROPA TRITON)

  defp matrix(programs, subscription_product_ids, opts \\ []) do
    Classifier.classify(programs, subscription_product_ids, opts)
  end

  test "Tunic: included on every tier (Essential SKU present)" do
    m = matrix(@standard_programs, [@essential, @premium, @starter])

    assert m["starter"] == :included
    assert m["essential"] == :included
    assert m["premium"] == :included
    assert m["ultimate"] == :included
  end

  test "Cyberpunk: Essential purchase, Premium/Ultimate included" do
    m = matrix(@standard_programs, [@premium, @console])

    assert m["essential"] == :purchase
    assert m["premium"] == :included
    assert m["ultimate"] == :included
    assert m["starter"] == :purchase
  end

  test "EA Play title: Ultimate included (bundles EA Play), others unavailable" do
    m = matrix(~w(GPULTIMATE CALLISTO IO GANYMEDE), [@ea_play])

    assert m["essential"] == :unavailable
    assert m["premium"] == :unavailable
    assert m["ultimate"] == :included
    # Starter's own program (TRITON) isn't in this title's programs either.
    assert m["starter"] == :unavailable
  end

  test "purchase-to-stream only: not in any subscription" do
    m = matrix(@standard_programs, [])

    assert m["essential"] == :purchase
    assert m["premium"] == :purchase
    assert m["ultimate"] == :purchase
    assert m["starter"] == :purchase
  end

  test "free-to-play: every tier is free" do
    m = matrix(["F2P"], [])

    assert m["starter"] == :free
    assert m["essential"] == :free
    assert m["premium"] == :free
    assert m["ultimate"] == :free
  end

  test "free? option forces free even without F2P program" do
    m = matrix(@standard_programs, [@premium], free?: true)
    assert Enum.all?(~w(starter essential premium ultimate), &(m[&1] == :free))
  end

  test "tier hierarchy: Essential SKU confers Premium and Ultimate inclusion" do
    m = matrix(@standard_programs, [@essential])

    assert m["essential"] == :included
    assert m["premium"] == :included
    assert m["ultimate"] == :included
  end

  test "Ubisoft+ (non-bundled) SKU does not confer GP tier inclusion" do
    ubisoft = "CFQ7TTC0QH5H"
    m = matrix(@standard_programs, [ubisoft])

    assert m["essential"] == :purchase
    assert m["premium"] == :purchase
    assert m["ultimate"] == :purchase
  end

  test "streamable? reflects any streamable tier" do
    assert Classifier.classify(@standard_programs, []) |> Classifier.streamable?()
    refute Classifier.classify(~w(GANYMEDE), []) |> Classifier.streamable?()
  end
end
