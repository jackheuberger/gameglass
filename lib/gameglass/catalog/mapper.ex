defmodule Gameglass.Catalog.Mapper do
  @moduledoc """
  Translates a `RawProduct` from the Xbox catalog into the normalized
  attributes Gameglass persists, plus the classification inputs.
  """

  alias Gameglass.Catalog.Classifier
  alias Gameglass.Catalog.Types.{RawProduct, ScannedGame}

  @doc """
  Builds a normalized scanned game from a typed raw product.

  Returns a `ScannedGame.t()`, or `nil` when the product is not a streamable cloud
  title (no `CLOUDGAMING` offering, e.g. an edition or bundle wrapper).
  """
  @spec normalize(RawProduct.t(), keyword()) :: ScannedGame.t() | nil
  def normalize(raw, opts \\ [])

  def normalize(%RawProduct{cloud_gaming?: false}, _opts), do: nil

  def normalize(%RawProduct{} = raw, opts) do
    xcloud_title_id = blank_to_nil(raw.xcloud_title_id)
    free? = "F2P" in raw.programs
    tiers = Classifier.classify(raw.programs, raw.subscription_product_ids, free?: free?)

    %ScannedGame{
      id: xcloud_title_id || raw.product_id,
      xcloud_title_id: xcloud_title_id,
      market: Keyword.get(opts, :market, "US"),
      title: raw.title,
      publisher: raw.publisher,
      developer: raw.developer,
      base_product_id: raw.product_id,
      xbox_title_id: parse_int(raw.xbox_title_id),
      image_url: normalize_image(raw.image_url),
      streamable: Classifier.streamable?(tiers),
      is_free: free?,
      price_value: raw.price_value,
      price_formatted: raw.price_formatted,
      price_currency: raw.price_currency,
      programs: raw.programs,
      tiers: tiers,
      subscription_product_ids: raw.subscription_product_ids
    }
  end

  defp normalize_image("//" <> _ = url), do: "https:" <> url
  defp normalize_image(url), do: url

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
