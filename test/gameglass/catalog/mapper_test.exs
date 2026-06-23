defmodule Gameglass.Catalog.MapperTest do
  use ExUnit.Case, async: true

  alias Gameglass.Catalog.Mapper

  defp raw(overrides \\ %{}) do
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
  end

  test "normalizes a cloud title into game attrs + tier statuses" do
    %{game: game, tier_statuses: statuses} = Mapper.normalize("9NLRT31Z4RWM", raw())

    assert game.dedup_key == "TUNIC"
    assert game.xcloud_title_id == "TUNIC"
    assert game.base_product_id == "9NLRT31Z4RWM"
    assert game.xbox_title_id == 1_848_191_014
    assert game.title == "TUNIC"
    assert game.image_url == "https://store-images.example/tunic.png"
    assert game.streamable
    refute game.is_free
    assert game.price_value == 29.99
    assert game.price_formatted == "$29.99"
    assert length(statuses) == 4
  end

  test "returns nil for products without a CLOUDGAMING offering (editions/bundles)" do
    assert Mapper.normalize("9NFHQ2719J83", raw(%{"XCloudOfferings" => %{}})) == nil
  end

  test "falls back to product id as dedup_key when XCloudTitleId is blank" do
    %{game: game} =
      Mapper.normalize(
        "BT5P2X999VH2",
        raw(%{
          "XCloudTitleId" => "",
          "XCloudOfferings" => %{"CLOUDGAMING" => %{"Programs" => ["F2P"]}}
        })
      )

    assert game.dedup_key == "BT5P2X999VH2"
    assert game.xcloud_title_id == nil
    assert game.is_free
  end
end
