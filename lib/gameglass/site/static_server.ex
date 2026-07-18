defmodule Gameglass.Site.StaticServer do
  @moduledoc """
  Minimal plug for `mix gameglass.serve`: serves the built `_site/` directory
  exactly as a static host would (`/` -> `index.html`, otherwise 404). Local
  dev preview only.
  """

  @behaviour Plug

  @impl true
  @spec init(String.t()) :: map()
  def init(root), do: Plug.Static.init(at: "/", from: root)

  @impl true
  def call(conn, opts) do
    conn = %{conn | path_info: rewrite(conn.path_info)}

    case Plug.Static.call(conn, opts) do
      %{halted: true} = served -> served
      missed -> Plug.Conn.send_resp(missed, 404, "not found")
    end
  end

  defp rewrite([]), do: ["index.html"]
  defp rewrite(path_info), do: path_info
end
