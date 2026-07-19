defmodule Gameglass.Catalog.Classifier do
  @moduledoc """
  Derives the streamability matrix for a game from the signals exposed by the
  catalog API:

    * `program_codes` - `XCloudOfferings.CLOUDGAMING.Programs`, the xCloud
      programs that allow a tier to stream *with an entitlement*
      (TRITON→Starter, EUROPA→Essential, DIA→Premium, CALLISTO→Ultimate).
    * `subscription_product_ids` - the keys of `PassMetadataByPassProductId`,
      the Game Pass SKUs that *include* the game for free.

  Neither signal alone is sufficient: Tunic (Essential-included) and Cyberpunk
  (Essential-purchase) carry identical program codes; the difference is
  whether the Essential SKU appears in subscription metadata to grant the user an entitlement.
  """

  alias Gameglass.Catalog.Tiers
  alias Gameglass.Catalog.Types.Tier

  @free_program "F2P"

  @doc """
  Returns a map from each configured tier key to its status.

  Options:

    * `:free?` - force the free-to-play result for every tier (e.g. when the
      product is flagged `isFreeInStore`). Defaults to `false`.
  """
  @spec classify(
          [Tier.program_code()],
          [Tier.subscription_product_id()],
          free?: boolean()
        ) :: Tier.statuses()
  def classify(program_codes, subscription_product_ids, opts \\ []) do
    program_codes = MapSet.new(program_codes)
    subscription_product_ids = MapSet.new(subscription_product_ids)

    free? =
      Keyword.get(opts, :free?, false) or MapSet.member?(program_codes, @free_program)

    Map.new(Tiers.all(), fn tier ->
      {tier.key, status_for(tier, program_codes, subscription_product_ids, free?)}
    end)
  end

  @doc "Returns true if any tier can stream the game (free, included, or purchasable)."
  @spec streamable?(Tier.statuses()) :: boolean()
  def streamable?(statuses) do
    Enum.any?(statuses, fn {_tier, status} -> status in ~w(free included purchase)a end)
  end

  @spec status_for(
          Tier.t(),
          MapSet.t(Tier.program_code()),
          MapSet.t(Tier.subscription_product_id()),
          boolean()
        ) ::
          Tier.status()
  defp status_for(tier, program_codes, subscription_product_ids, free?) do
    cond do
      free? -> :free
      included?(tier, subscription_product_ids) -> :included
      MapSet.member?(program_codes, tier.program_code) -> :purchase
      true -> :unavailable
    end
  end

  @spec included?(Tier.t(), MapSet.t(Tier.subscription_product_id())) :: boolean()
  defp included?(tier, subscription_product_ids) do
    included_ids = MapSet.new(tier.included_subscription_product_ids)
    not MapSet.disjoint?(included_ids, subscription_product_ids)
  end
end
