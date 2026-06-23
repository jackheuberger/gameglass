defmodule Gameglass.Catalog.Entitlement do
  @moduledoc """
  Join between a `Product` (an entitlement path) and a `Game` (a streamable
  unit) it grants access to. A multi-game bundle has several entitlements.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "product_game_entitlements" do
    belongs_to :product, Gameglass.Catalog.Product, foreign_key: :product_ref
    belongs_to :game, Gameglass.Catalog.Game

    timestamps(type: :utc_datetime)
  end

  def changeset(entitlement, attrs) do
    entitlement
    |> cast(attrs, [:product_ref, :game_id])
    |> validate_required([:product_ref, :game_id])
    |> unique_constraint([:product_ref, :game_id])
  end
end
