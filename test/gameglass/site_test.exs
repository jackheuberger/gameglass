defmodule Gameglass.SiteTest do
  use ExUnit.Case, async: true

  alias Gameglass.Catalog.{Mapper, Store}
  alias Gameglass.Catalog.Types.RawProduct
  alias Gameglass.Site
  alias Gameglass.Site.StaticServer

  @moduletag :tmp_dir

  @programs ~w(GPULTIMATE CALLISTO DIA EUROPA TRITON)
  @premium "CFQ7TTC0P85B"

  defp seed(data_dir) do
    raw = %{
      "ProductTitle" => "TUNIC",
      "XCloudTitleId" => "TUNIC",
      "XboxTitleId" => "1848191014",
      "XCloudOfferings" => %{"CLOUDGAMING" => %{"Programs" => @programs}},
      "PassMetadataByPassProductId" => %{@premium => %{}},
      "AnonymousPrice" => %{
        "MSRP" => %{"value" => 29.99, "formattedValue" => "$29.99", "currencyCode" => "USD"}
      }
    }

    record = "9NLRT31Z4RWM" |> RawProduct.from_json(raw) |> Mapper.normalize()
    {:ok, _} = Store.commit(data_dir, [record], MapSet.new(["9NLRT31Z4RWM"]))
  end

  setup %{tmp_dir: tmp_dir} do
    data_dir = Path.join(tmp_dir, "data")
    out_dir = Path.join(tmp_dir, "_site")
    %{data_dir: data_dir, out_dir: out_dir}
  end

  test "builds the shell, listing, and one file per lookup key", ctx do
    seed(ctx.data_dir)

    assert {:ok, %{games: 1, api_files: 3}} = Site.build(ctx.data_dir, ctx.out_dir)

    for file <- ~w(index.html app.js app.css .nojekyll api/games.json
                   api/by-product/9NLRT31Z4RWM.json api/by-xcloud/TUNIC.json
                   api/by-xbox/1848191014.json) do
      assert File.exists?(Path.join(ctx.out_dir, file)), "missing #{file}"
    end
  end

  test "lookup payloads keep the verify API shape", ctx do
    seed(ctx.data_dir)
    {:ok, _} = Site.build(ctx.data_dir, ctx.out_dir)

    payload =
      ctx.out_dir
      |> Path.join("api/by-product/9NLRT31Z4RWM.json")
      |> File.read!()
      |> Jason.decode!()

    assert %{"streamable" => true, "count" => 1, "games" => [g]} = payload
    assert g["xcloud_title_id"] == "TUNIC"
    assert g["product_id"] == "9NLRT31Z4RWM"
    assert g["tiers"]["premium"] == "included"
    assert g["tiers"]["essential"] == "purchase"
    assert g["price"] == %{"value" => 29.99, "formatted" => "$29.99", "currency" => "USD"}
    assert g["links"]["store"] == "https://www.xbox.com/games/store/tunic/9NLRT31Z4RWM"
    refute is_nil(g["last_verified_at"])
  end

  test "the listing carries stats, tier config and the last run", ctx do
    seed(ctx.data_dir)
    {:ok, _} = Site.build(ctx.data_dir, ctx.out_dir)

    listing =
      ctx.out_dir |> Path.join("api/games.json") |> File.read!() |> Jason.decode!()

    assert listing["count"] == 1
    assert Enum.map(listing["tiers"], & &1["key"]) == ~w(starter essential premium ultimate)
    assert listing["last_run"]["status"] == "success"
    assert [%{"links" => %{"store" => _}}] = listing["games"]
  end

  test "refuses to build without a snapshot", ctx do
    assert {:error, :no_data} = Site.build(ctx.data_dir, ctx.out_dir)
  end

  test "the preview server serves the home page and returns a plain 404", ctx do
    seed(ctx.data_dir)
    {:ok, _} = Site.build(ctx.data_dir, ctx.out_dir)
    opts = StaticServer.init(ctx.out_dir)

    home = Plug.Test.conn(:get, "/") |> StaticServer.call(opts)
    assert home.status == 200
    assert home.resp_body =~ "Xbox Cloud Gaming streamability"

    missing = Plug.Test.conn(:get, "/missing") |> StaticServer.call(opts)
    assert missing.status == 404
    assert missing.resp_body == "not found"
  end
end
