defmodule Gameglass.Catalog.Tiers do
  @moduledoc """
  Configuration data for the Xbox Game Pass subscription tiers that Gameglass
  reports on. Tiers are modeled as data (not hardcoded into the classification
  logic) so that subscription/program changes can be expressed here without
  touching the algorithm.

  Each tier carries:

    * `key`            - stable identifier used in the DB and API
    * `name`           - human-readable label
    * `rank`           - display/order and hierarchy (low to high)
    * `program_code`   - the xCloud program that lets this tier stream a game
                         *with an entitlement* (`nil` when not publicly known)
    * `pass_product_id`- this tier's own Game Pass SKU (BigId), if any
    * `included_pass_ids` - the set of Game Pass SKUs whose presence in a game's
                         `PassMetadataByPassProductId` means this tier includes
                         the game for free. This encodes the tier hierarchy
                         (e.g. Premium ⊃ Essential) and bundled subscriptions
                         (Ultimate bundles EA Play).

  Pass SKU reference (verified via displaycatalog):
    Essential CFQ7TTC0K5DJ, Premium CFQ7TTC0P85B, Ultimate CFQ7TTC0KHS0,
    Starter CFQ7TTC10QFD, EA Play CFQ7TTC0K5DH,
    Console GP CFQ7TTC0K6L8, PC GP CFQ7TTC0KGQ8 (Console/PC do not stream).
  """

  @starter "CFQ7TTC10QFD"
  @essential "CFQ7TTC0K5DJ"
  @premium "CFQ7TTC0P85B"
  @ultimate "CFQ7TTC0KHS0"
  @ea_play "CFQ7TTC0K5DH"

  @tiers [
    %{
      key: "starter",
      name: "Game Pass Starter",
      rank: 1,
      program_code: nil,
      pass_product_id: @starter,
      included_pass_ids: [@starter]
    },
    %{
      key: "essential",
      name: "Game Pass Essential",
      rank: 2,
      program_code: "EUROPA",
      pass_product_id: @essential,
      included_pass_ids: [@essential, @starter]
    },
    %{
      key: "premium",
      name: "Game Pass Premium",
      rank: 3,
      program_code: "DIA",
      pass_product_id: @premium,
      included_pass_ids: [@premium, @essential, @starter]
    },
    %{
      key: "ultimate",
      name: "Game Pass Ultimate",
      rank: 4,
      program_code: "CALLISTO",
      pass_product_id: @ultimate,
      included_pass_ids: [@ultimate, @premium, @essential, @starter, @ea_play]
    }
  ]

  @doc "All tiers, ordered low to high rank."
  def all, do: @tiers

  @doc "Tier keys, ordered low to high rank."
  def keys, do: Enum.map(@tiers, & &1.key)

  @doc "Fetch a tier config by key."
  def get(key), do: Enum.find(@tiers, &(&1.key == key))
end
