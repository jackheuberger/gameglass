defmodule Gameglass.Catalog.Types.StoredSnapshot do
  @moduledoc "The complete decoded contents of `data/games.json`."

  alias Gameglass.Catalog.Types.Game

  @type t :: %__MODULE__{
          generated_at: String.t(),
          market: String.t(),
          count: non_neg_integer(),
          games: [Game.t()]
        }

  @enforce_keys [:generated_at, :market, :count, :games]
  @derive Jason.Encoder
  defstruct [:generated_at, :market, :count, :games]

  @doc "Rebuilds a snapshot from the decoded contents of `games.json`."
  @spec from_json(map()) :: t()
  def from_json(data) do
    %__MODULE__{
      generated_at: data["generated_at"],
      market: data["market"],
      count: data["count"],
      games: Enum.map(data["games"] || [], &Game.from_json/1)
    }
  end
end
