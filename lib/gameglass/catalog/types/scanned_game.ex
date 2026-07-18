defmodule Gameglass.Catalog.Types.ScannedGame do
  @moduledoc """
  One normalized game produced by the current catalog scan.

  It contains only data observed during this scan. `Gameglass.Catalog.Store`
  reconciles it with prior scans to produce a persisted `Game` with tracking
  dates and historical product IDs.
  """

  alias Gameglass.Catalog.Types.Tier

  @type t :: %__MODULE__{
          id: String.t(),
          xcloud_title_id: String.t() | nil,
          market: String.t(),
          title: String.t() | nil,
          publisher: String.t() | nil,
          developer: String.t() | nil,
          base_product_id: String.t(),
          xbox_title_id: integer() | nil,
          image_url: String.t() | nil,
          streamable: boolean(),
          is_free: boolean(),
          price_value: number() | nil,
          price_formatted: String.t() | nil,
          price_currency: String.t() | nil,
          programs: [Tier.program_code()],
          tiers: Tier.statuses(),
          subscription_product_ids: [Tier.subscription_product_id()]
        }

  @enforce_keys [
    :id,
    :market,
    :base_product_id,
    :streamable,
    :is_free,
    :programs,
    :tiers,
    :subscription_product_ids
  ]
  defstruct [
    :id,
    :xcloud_title_id,
    :market,
    :title,
    :publisher,
    :developer,
    :base_product_id,
    :xbox_title_id,
    :image_url,
    :streamable,
    :is_free,
    :price_value,
    :price_formatted,
    :price_currency,
    :programs,
    :tiers,
    :subscription_product_ids
  ]
end
