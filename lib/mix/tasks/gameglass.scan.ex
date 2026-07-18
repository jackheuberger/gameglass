defmodule Mix.Tasks.Gameglass.Scan do
  @shortdoc "Scans the public Xbox catalog and updates data/*.json(l)"

  @moduledoc """
  Runs one full crawl of the anonymous public Xbox catalog and reconciles it
  into the data dir (see `Gameglass.Scanner`).

      mix gameglass.scan [--data-dir data] [--market US]

  Every run — success or failure — is appended to `runs.jsonl`.
  """

  use Mix.Task

  @requirements ["app.start"]

  @impl true
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: [data_dir: :string, market: :string])

    case Gameglass.Scanner.scan(opts) do
      {:ok, summary} ->
        Mix.shell().info(
          "Scan complete: #{summary.cloud_titles} cloud titles " <>
            "(+#{summary.added} added, -#{summary.removed} removed, " <>
            "#{summary.changed} changed) in #{summary.duration_ms}ms"
        )

      {:error, reason} ->
        Mix.raise("Scan failed: #{inspect(reason)}")
    end
  end
end
