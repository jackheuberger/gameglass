defmodule Gameglass.Catalog.ClientTest do
  use ExUnit.Case, async: true

  alias Gameglass.Catalog.Client

  test "fetches every product batch" do
    plug = fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      products =
        body
        |> Jason.decode!()
        |> Map.fetch!("Products")
        |> Map.new(&{&1, %{"ProductTitle" => &1}})

      json_response(conn, 200, %{"Products" => products})
    end

    assert {:ok, products} =
             Client.fetch_products(~w(A B C),
               batch_size: 2,
               req_options: [plug: plug, max_retries: 0]
             )

    assert Map.keys(products) |> Enum.sort() == ~w(A B C)
    assert products["A"].title == "A"
    assert products["A"].product_id == "A"
  end

  test "aborts instead of committing a partial scan when a batch fails" do
    plug = fn conn -> json_response(conn, 503, %{"error" => "temporarily unavailable"}) end

    assert {:error, {:products_batch_failed, 1, {:http_status, 503, _body}}} =
             Client.fetch_products(["A"],
               batch_size: 1,
               req_options: [plug: plug, max_retries: 0]
             )
  end

  test "uses an explicit market over the default" do
    assert Client.market(market: "GB") == "GB"
  end

  defp json_response(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end
end
