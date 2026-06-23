defmodule Gameglass.Repo do
  use Ecto.Repo,
    otp_app: :gameglass,
    adapter: Ecto.Adapters.SQLite3
end
