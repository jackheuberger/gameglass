defmodule Mix.Tasks.Gameglass.BuildSite do
  @shortdoc "Renders the static site from data/ into _site/"

  @moduledoc """
  Renders the static site — the matrix page plus one pre-resolved JSON file per
  API lookup key — from the committed data files (see `Gameglass.Site`).

      mix gameglass.build_site [--data-dir data] [--out _site]
  """

  use Mix.Task

  @requirements ["app.start"]

  @impl true
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: [data_dir: :string, out: :string])
    data_dir = opts[:data_dir] || "data"
    out_dir = opts[:out] || "_site"

    case Gameglass.Site.build(data_dir, out_dir) do
      {:ok, summary} ->
        Mix.shell().info(
          "Site built at #{out_dir}/ -- #{summary.games} games, #{summary.api_files} API files"
        )

      {:error, :no_data} ->
        Mix.raise("No snapshot at #{data_dir}/games.json — run `mix gameglass.scan` first.")
    end
  end
end
