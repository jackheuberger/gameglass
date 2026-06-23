defmodule Gameglass.Catalog.Product do
  @moduledoc """
  A store entity keyed by `productId`/BigId. Every base game, edition, and
  multi-game bundle is a product. A product is an *entitlement path*: it may
  grant access to one or more streamable `Game`s.

  `kind` is one of `"game"`, `"edition"`, or `"bundle"`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(game edition bundle)

  schema "products" do
    field :product_id, :string
    field :market, :string, default: "US"
    field :title, :string
    field :kind, :string, default: "game"
    field :xcloud_title_id, :string
    field :price_value, :float
    field :price_formatted, :string
    field :price_currency, :string
    field :last_verified_at, :utc_datetime

    has_many :entitlements, Gameglass.Catalog.Entitlement, foreign_key: :product_ref

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds

  def changeset(product, attrs) do
    product
    |> cast(attrs, [
      :product_id,
      :market,
      :title,
      :kind,
      :xcloud_title_id,
      :price_value,
      :price_formatted,
      :price_currency,
      :last_verified_at
    ])
    |> validate_required([:product_id, :market, :kind])
    |> validate_inclusion(:kind, @kinds)
    |> unique_constraint([:product_id, :market])
  end
end
