defmodule Gameglass.Catalog.Classifier do
  @moduledoc """
  Pure logic that derives the per-tier streamability matrix for a game from the
  two signals exposed by the anonymous catalog API:

    * `programs`        - `XCloudOfferings.CLOUDGAMING.Programs`, the xCloud
                          programs that allow a tier to stream *with an
                          entitlement* (EUROPA→Essential, DIA→Premium,
                          CALLISTO→Ultimate).
    * `pass_product_ids`- the keys of `PassMetadataByPassProductId`, the Game
                          Pass SKUs that *include* the game for free.

  Neither signal alone is sufficient: Tunic (Essential-included) and Cyberpunk
  (Essential-purchase) carry identical `programs`; the difference is whether the
  Essential SKU appears in pass metadata.
  """

  alias Gameglass.Catalog.Tiers

  @free_program "F2P"

  @doc """
  Returns a list of `%{tier_key, status}` maps, one per configured tier.

  Options:

    * `:free?` - force the free-to-play result for every tier (e.g. when the
      product is flagged `isFreeInStore`). Defaults to `false`.
  """
  def classify(programs, pass_product_ids, opts \\ []) do
    programs = MapSet.new(programs || [])
    pass = MapSet.new(pass_product_ids || [])
    free? = Keyword.get(opts, :free?, false) or MapSet.member?(programs, @free_program)

    Enum.map(Tiers.all(), fn tier ->
      %{tier_key: tier.key, status: status_for(tier, programs, pass, free?)}
    end)
  end

  @doc "Returns true if any tier can stream the game (free, included, or purchasable)."
  def streamable?(tier_statuses) do
    Enum.any?(tier_statuses, fn %{status: s} -> s in ~w(free included purchase) end)
  end

  defp status_for(tier, programs, pass, free?) do
    cond do
      free? ->
        "free"

      included?(tier, pass) ->
        "included"

      # Without a known program code (Starter) we cannot tell whether a
      # non-included game is purchasable, so report it as unknown.
      is_nil(tier.program_code) ->
        "unknown"

      MapSet.member?(programs, tier.program_code) ->
        "purchase"

      true ->
        "unavailable"
    end
  end

  defp included?(tier, pass) do
    tier.included_pass_ids
    |> MapSet.new()
    |> MapSet.intersection(pass)
    |> MapSet.size() > 0
  end
end
