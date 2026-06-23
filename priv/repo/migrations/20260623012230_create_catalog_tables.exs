defmodule Gameglass.Repo.Migrations.CreateCatalogTables do
  use Ecto.Migration

  def change do
    # A Game is the canonical streamable unit, keyed by XCloudTitleId.
    create table(:games) do
      add :dedup_key, :string, null: false
      add :xcloud_title_id, :string
      add :market, :string, null: false, default: "US"
      add :title, :string
      add :publisher, :string
      add :developer, :string
      add :base_product_id, :string
      add :xbox_title_id, :integer
      add :image_url, :string
      add :streamable, :boolean, null: false, default: true
      add :is_free, :boolean, null: false, default: false
      add :price_value, :float
      add :price_formatted, :string
      add :price_currency, :string
      add :programs, {:array, :string}, null: false, default: []
      add :first_seen_at, :utc_datetime
      add :last_verified_at, :utc_datetime
      add :last_changed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:games, [:dedup_key, :market])
    create index(:games, [:xcloud_title_id])
    create index(:games, [:streamable])
    create index(:games, [:title])

    # Per-(game, tier) streamability status. Normalized so tiers can change
    # without a schema migration.
    create table(:game_tier_statuses) do
      add :game_id, references(:games, on_delete: :delete_all), null: false
      add :tier_key, :string, null: false
      add :status, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:game_tier_statuses, [:game_id, :tier_key])
    create index(:game_tier_statuses, [:tier_key, :status])

    # A Product is any store entity (base game, edition, or bundle), keyed by
    # productId/BigId. It is an entitlement path that may grant one or more games.
    create table(:products) do
      add :product_id, :string, null: false
      add :market, :string, null: false, default: "US"
      add :title, :string
      add :kind, :string, null: false, default: "game"
      add :xcloud_title_id, :string
      add :price_value, :float
      add :price_formatted, :string
      add :price_currency, :string
      add :last_verified_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:products, [:product_id, :market])

    # Many-to-many: a product grants entitlement to game(s) (supports bundles).
    create table(:product_game_entitlements) do
      add :product_ref, references(:products, on_delete: :delete_all), null: false
      add :game_id, references(:games, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:product_game_entitlements, [:product_ref, :game_id])
    create index(:product_game_entitlements, [:game_id])

    # Append-only change log powering "recently changed" and the watchdog value.
    create table(:change_events) do
      add :kind, :string, null: false
      add :xcloud_title_id, :string
      add :game_id, references(:games, on_delete: :nilify_all)
      add :tier_key, :string
      add :old_value, :string
      add :new_value, :string
      add :detail, :string
      add :occurred_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:change_events, [:occurred_at])
    create index(:change_events, [:kind])
    create index(:change_events, [:xcloud_title_id])
  end
end
