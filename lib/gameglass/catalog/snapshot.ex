defmodule Gameglass.Catalog.Snapshot do
  @moduledoc """
  Pure construction of a catalog snapshot from raw `/v3/products` (Sapphire
  hydration) enrichment results: normalize each product, drop non-cloud titles,
  and collapse editions sharing a streamable unit (`XCloudTitleId`) into one
  game per streamable unit.
  """

  alias Gameglass.Catalog.{Classifier, Client, Mapper}
  alias Gameglass.Catalog.Types.ScannedGame

  @doc """
  Builds normalized, deduplicated games from a `Client.product_index()`.

  Returns a list of `ScannedGame.t()`, one per streamable unit.
  """
  @spec build(Client.product_index(), keyword()) :: [ScannedGame.t()]
  def build(raw_products, opts \\ []) when is_map(raw_products) do
    raw_products
    |> Map.values()
    |> Enum.flat_map(fn product ->
      case Mapper.normalize(product, opts) do
        nil -> []
        game -> [game]
      end
    end)
    |> merge_editions()
  end

  @doc """
  Collapses normalized products to one game per streamable unit (XCloudTitleId).

  Several products (Standard/Deluxe/Premium editions) can share one streamable
  unit. The game is included on a tier if *any* edition is, so we merge pass
  metadata across the group and re-classify. The representative row (title,
  price, base product) is the edition with the richest pass metadata and lowest
  price — i.e. the standard edition.
  """
  @spec merge_editions([ScannedGame.t()]) :: [ScannedGame.t()]
  def merge_editions(games) do
    games
    |> Enum.group_by(& &1.id)
    |> Enum.map(&merge_group/1)
  end

  @spec merge_group({String.t(), [ScannedGame.t()]}) :: ScannedGame.t()
  defp merge_group({_key, [single]}), do: single

  defp merge_group({_key, games}) do
    representative = Enum.min_by(games, &representative_rank/1)

    subscription_product_ids =
      games |> Enum.flat_map(& &1.subscription_product_ids) |> Enum.uniq()

    programs = games |> Enum.flat_map(& &1.programs) |> Enum.uniq()
    free? = Enum.any?(games, & &1.is_free)
    tiers = Classifier.classify(programs, subscription_product_ids, free?: free?)

    %{
      representative
      | programs: programs,
        is_free: free?,
        streamable: Classifier.streamable?(tiers),
        tiers: tiers,
        subscription_product_ids: subscription_product_ids
    }
  end

  # Lower sorts first: prefer most pass metadata, then lowest price, then a
  # stable product-id tiebreak so selection is deterministic across runs.
  defp representative_rank(game) do
    {
      -length(game.subscription_product_ids),
      game.price_value || 1.0e12,
      game.base_product_id
    }
  end
end
