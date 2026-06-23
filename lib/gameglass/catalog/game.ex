defmodule Gameglass.Catalog.Game do
  @moduledoc """
  The canonical streamable unit on Xbox Cloud Gaming, keyed by `XCloudTitleId`.

  A game may be reachable via several store products (base, editions, bundles);
  those are tracked separately as `Product`s linked through entitlements.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "games" do
    field :dedup_key, :string
    field :xcloud_title_id, :string
    field :market, :string, default: "US"
    field :title, :string
    field :publisher, :string
    field :developer, :string
    field :base_product_id, :string
    field :xbox_title_id, :integer
    field :image_url, :string
    field :streamable, :boolean, default: true
    field :is_free, :boolean, default: false
    field :price_value, :float
    field :price_formatted, :string
    field :price_currency, :string
    field :programs, {:array, :string}, default: []
    field :first_seen_at, :utc_datetime
    field :last_verified_at, :utc_datetime
    field :last_changed_at, :utc_datetime

    has_many :tier_statuses, Gameglass.Catalog.TierStatus
    has_many :entitlements, Gameglass.Catalog.Entitlement

    timestamps(type: :utc_datetime)
  end

  @fields [
    :dedup_key,
    :xcloud_title_id,
    :market,
    :title,
    :publisher,
    :developer,
    :base_product_id,
    :xbox_title_id,
    :image_url,
    :streamable,
    :is_free,
    :price_value,
    :price_formatted,
    :price_currency,
    :programs,
    :first_seen_at,
    :last_verified_at,
    :last_changed_at
  ]

  def changeset(game, attrs) do
    game
    |> cast(attrs, @fields)
    |> validate_required([:dedup_key, :market])
    |> unique_constraint([:dedup_key, :market])
  end
end
