defmodule Gameglass.Site do
  @moduledoc """
  Renders the static site from a data dir into an output dir:

    * copies the static shell (`priv/site`: index.html, app.js, app.css) —
      the page loads `api/games.json` and does all filtering client-side
    * `api/games.json` - the full listing plus scan metadata
    * `api/by-product/:productId.json`, `api/by-xcloud/:xcloudTitleId.json`,
      `api/by-xbox/:xboxTitleId.json` - one pre-resolved verify payload per
      lookup key (a static host can't parse query strings, so every lookup
      gets its own path)

  Not-found is expressed by the host's 404, so the "found" payloads don't
  carry an error field.
  """

  require Logger

  alias Gameglass.Catalog.{Links, Resolve, Store, Tiers}
  alias Gameglass.Catalog.Types.{Game, Run, StoredSnapshot}

  # Identifiers become filenames; skip anything that couldn't be a safe basename.
  # Unicode letters occur in real XCloudTitleIds (VIVAPIÑATA, BRÜTALLEGEND);
  # the leading alphanumeric rules out dotfiles, "..", and path separators.
  @safe_id ~r/^[\p{L}\p{N}][\p{L}\p{N}._-]*$/u

  @doc "Builds the site. Returns `{:ok, %{games: n, api_files: n}}`."
  @spec build(String.t(), String.t()) ::
          {:ok, %{games: non_neg_integer(), api_files: non_neg_integer()}} | {:error, :no_data}
  def build(data_dir, out_dir) do
    case Store.load_snapshot(data_dir) do
      %StoredSnapshot{games: [_ | _]} = snapshot ->
        build_snapshot(snapshot, Store.last_run(data_dir), out_dir)

      _ ->
        {:error, :no_data}
    end
  end

  defp build_snapshot(snapshot, last_run, out_dir) do
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(out_dir, "api"))

    copy_shell(out_dir)
    write_listing(out_dir, snapshot, last_run)
    api_files = write_lookups(out_dir, snapshot.games, snapshot.generated_at)

    # Keep GitHub Pages from running the output through Jekyll.
    File.write!(Path.join(out_dir, ".nojekyll"), "")

    {:ok, %{games: length(snapshot.games), api_files: api_files}}
  end

  defp copy_shell(out_dir) do
    shell_dir = Path.join(:code.priv_dir(:gameglass), "site")

    for file <- File.ls!(shell_dir) do
      File.cp!(Path.join(shell_dir, file), Path.join(out_dir, file))
    end
  end

  @spec write_listing(String.t(), StoredSnapshot.t(), Run.t() | nil) :: :ok
  defp write_listing(out_dir, snapshot, last_run) do
    games = snapshot.games

    doc = %{
      "generated_at" => snapshot.generated_at,
      "market" => snapshot.market,
      "recent_days" => 7,
      "tiers" => Enum.map(Tiers.all(), &%{"key" => &1.key, "name" => &1.name}),
      "last_run" => last_run,
      "count" => Enum.count(games, & &1.streamable),
      "games" => Enum.map(games, &game_listing_json/1)
    }

    File.write!(Path.join(out_dir, "api/games.json"), Jason.encode_to_iodata!(doc))
  end

  # The full persisted game, JSON-shaped, plus links for the games.json listing.
  @spec game_listing_json(Game.t()) :: map()
  defp game_listing_json(game) do
    game
    |> Map.from_struct()
    |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)
    |> Map.put("links", links(game))
  end

  @spec write_lookups(String.t(), [Game.t()], String.t()) :: non_neg_integer()
  defp write_lookups(out_dir, games, generated_at) do
    indexes = Resolve.build(games)

    lookup_indexes = [
      {"by-product", indexes.by_product},
      {"by-xcloud", indexes.by_xcloud},
      {"by-xbox", indexes.by_xbox}
    ]

    Enum.reduce(lookup_indexes, 0, fn {subdir, index}, file_count ->
      dir = Path.join([out_dir, "api", subdir])
      File.mkdir_p!(dir)

      safe = Enum.filter(index, fn {id, _games} -> safe_id?(id) end)

      Enum.each(safe, fn {id, resolved} ->
        File.write!(
          Path.join(dir, "#{id}.json"),
          Jason.encode_to_iodata!(payload(resolved, generated_at))
        )
      end)

      file_count + length(safe)
    end)
  end

  defp safe_id?(id) do
    if Regex.match?(@safe_id, id) do
      true
    else
      Logger.warning("Gameglass site: skipping unsafe lookup id #{inspect(id)}")
      false
    end
  end

  # The verify payload, same shape the server API returned.
  @spec payload([Game.t()], String.t()) :: map()
  defp payload(games, generated_at) do
    %{
      "streamable" => Enum.any?(games, & &1.streamable),
      "count" => length(games),
      "games" => Enum.map(games, &game_json(&1, generated_at))
    }
  end

  @spec game_json(Game.t(), String.t()) :: map()
  defp game_json(game, generated_at) do
    %{
      "xcloud_title_id" => game.xcloud_title_id,
      "product_id" => game.base_product_id,
      "title" => game.title,
      "streamable" => game.streamable,
      "is_free" => game.is_free,
      "tiers" => game.tiers,
      "price" => price_json(game),
      "links" => links(game),
      # A present game was verified by the scan that generated the snapshot; a
      # removed game was last verified by the scan that noticed its absence.
      "last_verified_at" => game.removed_at || generated_at
    }
  end

  @spec price_json(Game.t()) :: map() | nil
  defp price_json(%Game{price_formatted: nil}), do: nil

  defp price_json(game) do
    %{
      "value" => game.price_value,
      "formatted" => game.price_formatted,
      "currency" => game.price_currency
    }
  end

  @spec links(Game.t()) :: map()
  defp links(game), do: Links.all(game.base_product_id, game.title)
end
