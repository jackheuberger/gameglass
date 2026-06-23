# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Gameglass has no static seed data — the catalog is populated by crawling the
# public Xbox catalog endpoints. To fill the database, run a refresh:
#
#     Gameglass.Ingest.refresh()
#
# or, with the app running, click "Refresh" in the UI / call:
#
#     Gameglass.Ingest.Refresher.refresh_async()
#
# A full refresh fetches ~3,000 cloud titles and takes roughly a minute.

require Logger

if System.get_env("SEED_INGEST") in ~w(1 true) do
  Logger.info("Seeding Gameglass via live catalog refresh…")
  {:ok, summary} = Gameglass.Ingest.refresh()
  Logger.info("Seed complete: #{inspect(summary)}")
else
  Logger.info(
    "Skipping live catalog ingest. Run Gameglass.Ingest.refresh() (or set " <>
      "SEED_INGEST=1 when running seeds) to populate the catalog."
  )
end
