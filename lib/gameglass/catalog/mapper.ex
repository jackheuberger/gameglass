defmodule Gameglass.Catalog.Mapper do
  @moduledoc """
  Translates a raw `v3/products` (Sapphire hydration) product map into the
  normalized attributes Gameglass persists, plus the classification inputs.
  """

  alias Gameglass.Catalog.Classifier

  @doc """
  Builds a normalized record from a raw product map.

  Returns `%{game: attrs, tier_statuses: [...], programs: [...], pass_ids: [...]}`
  or `nil` when the product is not a streamable cloud title (no `CLOUDGAMING`
  offering, e.g. an edition or bundle wrapper).
  """
  def normalize(product_id, raw) when is_map(raw) do
    cloud = get_in(raw, ["XCloudOfferings", "CLOUDGAMING"])

    if is_nil(cloud) do
      nil
    else
      programs = cloud["Programs"] || []
      pass_ids = Map.keys(raw["PassMetadataByPassProductId"] || %{})
      xcloud_title_id = blank_to_nil(raw["XCloudTitleId"])
      is_free = "F2P" in programs
      tier_statuses = Classifier.classify(programs, pass_ids, free?: is_free)

      price = raw["AnonymousPrice"]["MSRP"] || %{}

      game = %{
        dedup_key: xcloud_title_id || product_id,
        xcloud_title_id: xcloud_title_id,
        market: "US",
        title: raw["ProductTitle"],
        publisher: raw["PublisherName"],
        developer: raw["DeveloperName"],
        base_product_id: product_id,
        xbox_title_id: parse_int(raw["XboxTitleId"]),
        image_url: normalize_image(raw),
        streamable: Classifier.streamable?(tier_statuses),
        is_free: is_free,
        price_value: price["value"],
        price_formatted: price["formattedValue"],
        price_currency: price["currencyCode"],
        programs: programs
      }

      %{game: game, tier_statuses: tier_statuses, programs: programs, pass_ids: pass_ids}
    end
  end

  def normalize(_product_id, _), do: nil

  defp normalize_image(raw) do
    case get_in(raw, ["Image_Tile", "URL"]) || get_in(raw, ["Image_Poster", "URL"]) do
      "//" <> _ = url -> "https:" <> url
      url -> url
    end
  end

  defp parse_int(nil), do: nil
  defp parse_int(n) when is_integer(n), do: n

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(s) when is_binary(s), do: s
end
