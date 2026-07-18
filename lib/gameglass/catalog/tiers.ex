defmodule Gameglass.Catalog.Tiers do
  @moduledoc """
  Configuration data for the Xbox Game Pass subscription tiers that Gameglass
  reports on. Tiers are modeled as data (not hardcoded into the classification
  logic) so that subscription/program changes can be expressed here without
  touching the algorithm.

  Each tier carries:

    * `key` - stable identifier used in snapshots and the API
    * `name` - human-readable label
    * `program_code` - the xCloud program that lets this tier stream a game
      *with an entitlement*
    * `included_subscription_product_ids` - the Game Pass SKUs whose presence
      in a game's `PassMetadataByPassProductId` means this tier includes the
      game. This encodes the tier hierarchy (e.g. Premium ⊃ Essential) and
      bundled subscriptions (Ultimate bundles EA Play).

  Pass SKU reference (verified via displaycatalog):
    Essential CFQ7TTC0K5DJ, Premium CFQ7TTC0P85B, Ultimate CFQ7TTC0KHS0,
    Starter CFQ7TTC10QFD, EA Play CFQ7TTC0K5DH,
    Console GP CFQ7TTC0K6L8, PC GP CFQ7TTC0KGQ8 (Console/PC do not stream).
  """

  alias Gameglass.Catalog.Types.Tier

  @starter "CFQ7TTC10QFD"
  @essential "CFQ7TTC0K5DJ"
  @premium "CFQ7TTC0P85B"
  @ultimate "CFQ7TTC0KHS0"
  @ea_play "CFQ7TTC0K5DH"

  @tiers [
    %Tier{
      key: "starter",
      name: "Game Pass Starter",
      program_code: "TRITON",
      included_subscription_product_ids: [@starter]
    },
    %Tier{
      key: "essential",
      name: "Game Pass Essential",
      program_code: "EUROPA",
      included_subscription_product_ids: [@essential, @starter]
    },
    %Tier{
      key: "premium",
      name: "Game Pass Premium",
      program_code: "DIA",
      included_subscription_product_ids: [@premium, @essential, @starter]
    },
    %Tier{
      key: "ultimate",
      name: "Game Pass Ultimate",
      program_code: "CALLISTO",
      included_subscription_product_ids: [@ultimate, @premium, @essential, @starter, @ea_play]
    }
  ]

  @doc "All tiers, ordered from the lowest to highest access level."
  @spec all() :: [Tier.t()]
  def all, do: @tiers
end
