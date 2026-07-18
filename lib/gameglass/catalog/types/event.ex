defmodule Gameglass.Catalog.Types.Event do
  @moduledoc "One catalog change recorded in `data/changes.jsonl`."

  alias Gameglass.Catalog.Types.Tier

  @type kind :: :game_added | :game_removed | :tier_status_changed | :price_changed
  @type value :: String.t() | Tier.status() | nil

  @type t :: %__MODULE__{
          kind: kind(),
          game_id: String.t(),
          xcloud_title_id: String.t(),
          tier_key: Tier.key() | nil,
          old_value: value(),
          new_value: value(),
          detail: String.t() | nil,
          occurred_at: String.t(),
          run_id: pos_integer() | nil
        }

  @enforce_keys [:kind, :game_id, :xcloud_title_id, :occurred_at]
  @derive Jason.Encoder
  defstruct [
    :kind,
    :game_id,
    :xcloud_title_id,
    :tier_key,
    :old_value,
    :new_value,
    :detail,
    :occurred_at,
    :run_id
  ]

  @doc "Rebuilds an event from one decoded JSONL row."
  @spec from_json(map()) :: t()
  def from_json(data) do
    kind = parse_kind(data["kind"])

    %__MODULE__{
      kind: kind,
      game_id: data["game_id"],
      xcloud_title_id: data["xcloud_title_id"],
      tier_key: data["tier_key"],
      old_value: parse_value(kind, data["old_value"]),
      new_value: parse_value(kind, data["new_value"]),
      detail: data["detail"],
      occurred_at: data["occurred_at"],
      run_id: data["run_id"]
    }
  end

  defp parse_value(:tier_status_changed, value) when is_binary(value),
    do: Tier.parse_status(value)

  defp parse_value(_kind, value), do: value

  defp parse_kind("game_added"), do: :game_added
  defp parse_kind("game_removed"), do: :game_removed
  defp parse_kind("tier_status_changed"), do: :tier_status_changed
  defp parse_kind("price_changed"), do: :price_changed

  defp parse_kind(value),
    do: raise(ArgumentError, "unknown event kind: #{inspect(value)}")
end
