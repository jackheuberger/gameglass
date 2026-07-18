defmodule Gameglass.Catalog.Resolve do
  @moduledoc """
  Pure lookup indexes over a games snapshot, used to pre-render the static
  verify API. Mirrors the resolution paths of the old server API:

    * by product id (BigId) — the game's base product plus any other product
      ids known to grant it (`product_ids`, ready for edition/bundle expansion)
    * by `XCloudTitleId`
    * by `xboxTitleId`

  Each index maps an identifier to the list of games it resolves to (a bundle
  id can resolve to several games).
  """

  alias Gameglass.Catalog.Types.Game

  @type indexes :: %{
          by_product: %{String.t() => [Game.t()]},
          by_xcloud: %{String.t() => [Game.t()]},
          by_xbox: %{String.t() => [Game.t()]}
        }

  @doc "Builds all three indexes from a list of persisted games."
  @spec build([Game.t()]) :: indexes()
  def build(games) do
    %{
      by_product: index(games, &product_ids/1),
      by_xcloud: index(games, &List.wrap(&1.xcloud_title_id)),
      by_xbox: index(games, fn g -> g.xbox_title_id |> List.wrap() |> Enum.map(&to_string/1) end)
    }
  end

  @doc "Resolves an identifier against built indexes. Returns a (possibly empty) list."
  @spec lookup(indexes(), :product_id | :xcloud_title_id, String.t()) :: [Game.t()]
  @spec lookup(indexes(), :xbox_title_id, String.t() | integer()) :: [Game.t()]
  def lookup(indexes, :product_id, value), do: Map.get(indexes.by_product, value, [])
  def lookup(indexes, :xcloud_title_id, value), do: Map.get(indexes.by_xcloud, value, [])

  def lookup(indexes, :xbox_title_id, value),
    do: Map.get(indexes.by_xbox, to_string(value), [])

  defp product_ids(game) do
    [game.base_product_id | game.product_ids]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp index(games, keys_fun) do
    for game <- games, key <- keys_fun.(game), reduce: %{} do
      acc -> Map.update(acc, key, [game], &(&1 ++ [game]))
    end
  end
end
