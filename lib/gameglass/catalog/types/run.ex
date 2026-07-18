defmodule Gameglass.Catalog.Types.Run do
  @moduledoc "One scan audit record stored in `data/runs.jsonl`."

  @type status :: :success | :failed

  @type t :: %__MODULE__{
          id: pos_integer(),
          started_at: String.t(),
          finished_at: String.t(),
          status: status(),
          enumerated: non_neg_integer() | nil,
          from_sigl: non_neg_integer() | nil,
          from_subscriptions: non_neg_integer() | nil,
          enriched: non_neg_integer() | nil,
          cloud_titles: non_neg_integer() | nil,
          added: non_neg_integer() | nil,
          removed: non_neg_integer() | nil,
          changed: non_neg_integer() | nil,
          duration_ms: non_neg_integer(),
          error: String.t() | nil
        }

  @enforce_keys [:id, :started_at, :finished_at, :status, :duration_ms]
  @derive Jason.Encoder
  defstruct [
    :id,
    :started_at,
    :finished_at,
    :status,
    :enumerated,
    :from_sigl,
    :from_subscriptions,
    :enriched,
    :cloud_titles,
    :added,
    :removed,
    :changed,
    :duration_ms,
    :error
  ]

  @doc "Rebuilds a scan run from one decoded JSONL row."
  @spec from_json(map()) :: t()
  def from_json(data) do
    %__MODULE__{
      id: data["id"],
      started_at: data["started_at"],
      finished_at: data["finished_at"],
      status: parse_status(data["status"]),
      enumerated: data["enumerated"],
      from_sigl: data["from_sigl"],
      from_subscriptions: data["from_subscriptions"],
      enriched: data["enriched"],
      cloud_titles: data["cloud_titles"],
      added: data["added"],
      removed: data["removed"],
      changed: data["changed"],
      duration_ms: data["duration_ms"],
      error: data["error"]
    }
  end

  defp parse_status("success"), do: :success
  defp parse_status("failed"), do: :failed

  defp parse_status(value),
    do: raise(ArgumentError, "unknown scan status: #{inspect(value)}")
end
