defmodule Gameglass.Catalog.MapperTest do
  use ExUnit.Case, async: true

  alias Gameglass.Catalog.Mapper
  alias Gameglass.Catalog.Types.RawProduct

  defp raw(overrides \\ %{}) do
    raw("9NLRT31Z4RWM", overrides)
  end

  defp raw(product_id, overrides) do
    payload =
      Map.merge(
        %{
          "ProductTitle" => "TUNIC",
          "PublisherName" => "Finji",
          "DeveloperName" => "ISOMETRICORP Games Ltd",
          "XCloudTitleId" => "TUNIC",
          "XboxTitleId" => "1848191014",
          "Image_Tile" => %{"URL" => "//store-images.example/tunic.png"},
          "Streamability" => %{"WithGPU" => true},
          "XCloudOfferings" => %{
            "CLOUDGAMING" => %{"Programs" => ~w(GPULTIMATE CALLISTO DIA EUROPA TRITON)}
          },
          "PassMetadataByPassProductId" => %{"CFQ7TTC0K5DJ" => %{}, "CFQ7TTC0P85B" => %{}},
          "AnonymousPrice" => %{
            "MSRP" => %{"value" => 29.99, "formattedValue" => "$29.99", "currencyCode" => "USD"}
          }
        },
        overrides
      )

    RawProduct.from_json(product_id, payload)
  end

  test "normalizes a cloud title into game attrs + tier statuses" do
    game = Mapper.normalize(raw())

    assert game.id == "TUNIC"
    assert game.xcloud_title_id == "TUNIC"
    assert game.base_product_id == "9NLRT31Z4RWM"
    assert game.xbox_title_id == 1_848_191_014
    assert game.title == "TUNIC"
    assert game.image_url == "https://store-images.example/tunic.png"
    assert game.streamable
    refute game.is_free
    assert game.price_value == 29.99
    assert game.price_formatted == "$29.99"
    assert map_size(game.tiers) == 4
  end

  test "returns nil for products without a CLOUDGAMING offering (editions/bundles)" do
    assert is_nil(Mapper.normalize(raw(%{"XCloudOfferings" => %{}})))
  end

  test "uses the product id when XCloudTitleId is blank" do
    game =
      Mapper.normalize(
        raw("BT5P2X999VH2", %{
          "XCloudTitleId" => "",
          "XCloudOfferings" => %{"CLOUDGAMING" => %{"Programs" => ["F2P"]}}
        })
      )

    assert game.id == "BT5P2X999VH2"
    assert is_nil(game.xcloud_title_id)
    assert game.is_free
  end

  test "uses the requested market" do
    game = Mapper.normalize(raw(), market: "GB")
    assert game.market == "GB"
  end
end
