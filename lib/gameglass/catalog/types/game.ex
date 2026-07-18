defmodule Gameglass.Catalog.Types.Game do
  @moduledoc """
  One persisted game in `data/games.json`.

  In addition to the latest scanned catalog fields, it records when Gameglass
  first saw and last changed the game, when it entered or left the catalog,
  and every product ID known to grant it.
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
          first_seen_at: String.t(),
          last_changed_at: String.t(),
          added_at: String.t() | nil,
          removed_at: String.t() | nil,
          product_ids: [String.t()]
        }

  @enforce_keys [
    :id,
    :market,
    :base_product_id,
    :streamable,
    :is_free,
    :programs,
    :tiers,
    :first_seen_at,
    :last_changed_at,
    :product_ids
  ]
  @derive Jason.Encoder
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
    :first_seen_at,
    :last_changed_at,
    :added_at,
    :removed_at,
    :product_ids
  ]

  @doc "Rebuilds a game from its decoded JSON representation."
  @spec from_json(map()) :: t()
  def from_json(data) do
    %__MODULE__{
      id: data["id"],
      xcloud_title_id: data["xcloud_title_id"],
      market: data["market"],
      title: data["title"],
      publisher: data["publisher"],
      developer: data["developer"],
      base_product_id: data["base_product_id"],
      xbox_title_id: data["xbox_title_id"],
      image_url: data["image_url"],
      streamable: data["streamable"],
      is_free: data["is_free"],
      price_value: data["price_value"],
      price_formatted: data["price_formatted"],
      price_currency: data["price_currency"],
      programs: data["programs"] || [],
      tiers:
        Map.new(data["tiers"] || %{}, fn {key, value} ->
          {key, Tier.parse_status(value)}
        end),
      first_seen_at: data["first_seen_at"],
      last_changed_at: data["last_changed_at"],
      added_at: data["added_at"],
      removed_at: data["removed_at"],
      product_ids: data["product_ids"] || []
    }
  end
end
