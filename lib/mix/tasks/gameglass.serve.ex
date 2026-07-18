defmodule Mix.Tasks.Gameglass.Serve do
  @shortdoc "Serves the built _site/ locally for preview"

  @moduledoc """
  Serves the built static site on localhost, exactly as a static host would.
  Local dev preview only — production hosting is GitHub Pages.

      mix gameglass.serve [--site-dir _site] [--port 4000]
  """

  use Mix.Task

  @requirements ["app.start"]

  @impl true
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: [site_dir: :string, port: :integer])
    site_dir = opts[:site_dir] || "_site"
    port = opts[:port] || 4000

    unless File.exists?(Path.join(site_dir, "index.html")) do
      Mix.raise("No site at #{site_dir}/ — run `mix gameglass.build_site` first.")
    end

    {:ok, _} =
      Bandit.start_link(plug: {Gameglass.Site.StaticServer, site_dir}, port: port)

    Mix.shell().info("Serving #{site_dir}/ at http://localhost:#{port} (ctrl-c to stop)")
    Process.sleep(:infinity)
  end
end
