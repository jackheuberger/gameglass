defmodule Gameglass.Catalog.Types.RawProduct do
  @moduledoc """
  The small part of an Xbox `/v3/products` response that Gameglass uses.

  The upstream product document contains many fields and uses deeply nested,
  string-keyed JSON maps. `from_json/2` projects that document into a typed
  struct as soon as it enters the application. The rest of the catalog code
  can then work with named fields and ignore unrelated API details.

  This is still an input type: domain decisions such as tier classification,
  URL normalization, and integer parsing belong in `Gameglass.Catalog.Mapper`.
  """

  alias Gameglass.Catalog.Types.Tier

  @type t :: %__MODULE__{
          product_id: String.t(),
          title: String.t() | nil,
          publisher: String.t() | nil,
          developer: String.t() | nil,
          xcloud_title_id: String.t() | nil,
          xbox_title_id: String.t() | integer() | nil,
          image_url: String.t() | nil,
          cloud_gaming?: boolean(),
          programs: [Tier.program_code()],
          subscription_product_ids: [Tier.subscription_product_id()],
          price_value: number() | nil,
          price_formatted: String.t() | nil,
          price_currency: String.t() | nil
        }

  @enforce_keys [:product_id, :cloud_gaming?, :programs, :subscription_product_ids]
  defstruct [
    :product_id,
    :title,
    :publisher,
    :developer,
    :xcloud_title_id,
    :xbox_title_id,
    :image_url,
    :price_value,
    :price_formatted,
    :price_currency,
    cloud_gaming?: false,
    programs: [],
    subscription_product_ids: []
  ]

  @doc "Builds the typed projection of one decoded Xbox product document."
  @spec from_json(String.t(), map()) :: t()
  def from_json(product_id, payload) when is_binary(product_id) and is_map(payload) do
    cloud_offering = get_in(payload, ["XCloudOfferings", "CLOUDGAMING"])
    price = get_in(payload, ["AnonymousPrice", "MSRP"]) || %{}

    %__MODULE__{
      product_id: product_id,
      title: payload["ProductTitle"],
      publisher: payload["PublisherName"],
      developer: payload["DeveloperName"],
      xcloud_title_id: payload["XCloudTitleId"],
      xbox_title_id: payload["XboxTitleId"],
      image_url: image_url(payload),
      cloud_gaming?: is_map(cloud_offering),
      programs: programs(cloud_offering),
      subscription_product_ids: subscription_product_ids(payload["PassMetadataByPassProductId"]),
      price_value: price["value"],
      price_formatted: price["formattedValue"],
      price_currency: price["currencyCode"]
    }
  end

  defp image_url(payload) do
    get_in(payload, ["Image_Tile", "URL"]) || get_in(payload, ["Image_Poster", "URL"])
  end

  defp programs(%{"Programs" => values}) when is_list(values) do
    Enum.filter(values, &is_binary/1)
  end

  defp programs(_cloud_offering), do: []

  defp subscription_product_ids(values) when is_map(values) do
    values
    |> Map.keys()
    |> Enum.filter(&is_binary/1)
  end

  defp subscription_product_ids(_values), do: []
end
