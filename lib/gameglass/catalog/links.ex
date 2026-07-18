defmodule Gameglass.Catalog.Links do
  @moduledoc """
  Builds external Xbox URLs for a product: the store page, the legacy cloud
  gaming client (`www.xbox.com/play`), and the new client (`play.xbox.com`).

  The product id (BigId) is what resolves each page; the title slug is cosmetic.
  """

  @type product_id :: String.t()

  @doc "Xbox Store product page."
  @spec store(product_id(), String.t() | nil) :: String.t()
  def store(product_id, title \\ nil),
    do: "https://www.xbox.com/games/store/#{slug(title)}/#{product_id}"

  @doc "Legacy cloud gaming client product page (www.xbox.com/play)."
  @spec play_legacy(product_id(), String.t() | nil) :: String.t()
  def play_legacy(product_id, title \\ nil),
    do: "https://www.xbox.com/play/games/#{slug(title)}/#{product_id}"

  @doc "New cloud gaming client product page (play.xbox.com)."
  @spec play_new(product_id(), String.t() | nil) :: String.t()
  def play_new(product_id, title \\ nil),
    do: "https://play.xbox.com/products/#{product_id}/#{slug(title)}"

  @doc "All three links as a map."
  @spec all(product_id(), String.t() | nil) :: %{
          store: String.t(),
          play_legacy: String.t(),
          play_new: String.t()
        }
  def all(product_id, title \\ nil) do
    %{
      store: store(product_id, title),
      play_legacy: play_legacy(product_id, title),
      play_new: play_new(product_id, title)
    }
  end

  @doc "URL-safe slug from a title, e.g. \"EA SPORTS FC™ 25\" -> \"ea-sports-fc-25\"."
  @spec slug(String.t() | nil) :: String.t()
  def slug(nil), do: "_"
  def slug(""), do: "_"

  def slug(title) do
    slug =
      title
      |> String.downcase()
      |> String.normalize(:nfd)
      |> String.replace(~r/[^a-z0-9\s-]/u, "")
      |> String.replace(~r/[\s-]+/, "-")
      |> String.trim("-")

    if slug == "", do: "_", else: slug
  end
end
