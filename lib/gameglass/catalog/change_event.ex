defmodule Gameglass.Catalog.ChangeEvent do
  @moduledoc """
  Append-only record of a change detected during ingestion. Powers the
  "recently changed" view and Gameglass's role as an external watchdog.

  `kind` is one of:

    * `"game_added"`          - a game newly appeared in the cloud catalog
    * `"game_removed"`        - a game left the cloud catalog
    * `"streamable_changed"`  - a game's streamable flag flipped
    * `"tier_status_changed"` - a game's status for a tier changed
    * `"price_changed"`       - a game's price changed
  """
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(game_added game_removed streamable_changed tier_status_changed price_changed)

  schema "change_events" do
    field :kind, :string
    field :xcloud_title_id, :string
    field :tier_key, :string
    field :old_value, :string
    field :new_value, :string
    field :detail, :string
    field :occurred_at, :utc_datetime

    belongs_to :game, Gameglass.Catalog.Game
    belongs_to :run, Gameglass.Catalog.Run

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :kind,
      :xcloud_title_id,
      :game_id,
      :run_id,
      :tier_key,
      :old_value,
      :new_value,
      :detail,
      :occurred_at
    ])
    |> validate_required([:kind, :occurred_at])
    |> validate_inclusion(:kind, @kinds)
  end
end
