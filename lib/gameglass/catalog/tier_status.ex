defmodule Gameglass.Catalog.TierStatus do
  @moduledoc """
  The streamability status of a `Game` for a single subscription tier.

  Status values:

    * `"free"`        - free-to-play, streamable by anyone
    * `"included"`    - streams for free with this tier's subscription
    * `"purchase"`    - streamable on this tier only if the game is purchased
    * `"unavailable"` - not streamable on this tier even if purchased
    * `"unknown"`     - cannot be determined (e.g. Starter, no public program)
  """
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(free included purchase unavailable unknown)

  schema "game_tier_statuses" do
    field :tier_key, :string
    field :status, :string

    belongs_to :game, Gameglass.Catalog.Game

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(tier_status, attrs) do
    tier_status
    |> cast(attrs, [:game_id, :tier_key, :status])
    |> validate_required([:tier_key, :status])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint([:game_id, :tier_key])
  end
end
