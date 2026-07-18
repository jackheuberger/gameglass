defmodule Gameglass do
  @moduledoc """
  An external source of truth for Xbox Cloud Gaming streamability.

  Gameglass is a scanner + static-site generator: `mix gameglass.scan` crawls
  the anonymous public Xbox catalog and commits JSON snapshots under `data/`,
  and `mix gameglass.build_site` renders the matrix page and the pre-resolved
  verify API into `_site/`. The committed data files (and their git history)
  are the database and the audit trail.
  """
end
