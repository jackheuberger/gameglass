defmodule Gameglass.Catalog.Types.Tier do
  @moduledoc "A configured Xbox Game Pass tier and its possible game statuses."

  @type key :: String.t()
  @type program_code :: String.t()
  @type subscription_product_id :: String.t()
  @type status :: :free | :included | :purchase | :unavailable
  @type statuses :: %{key() => status()}

  @type t :: %__MODULE__{
          key: key(),
          name: String.t(),
          program_code: program_code(),
          included_subscription_product_ids: [subscription_product_id()]
        }

  @enforce_keys [
    :key,
    :name,
    :program_code,
    :included_subscription_product_ids
  ]
  defstruct [
    :key,
    :name,
    :program_code,
    :included_subscription_product_ids
  ]

  @doc "Parses a status read from JSON into one of the known status atoms."
  @spec parse_status(String.t()) :: status()
  def parse_status("free"), do: :free
  def parse_status("included"), do: :included
  def parse_status("purchase"), do: :purchase
  def parse_status("unavailable"), do: :unavailable

  def parse_status(value),
    do: raise(ArgumentError, "unknown tier status: #{inspect(value)}")
end
