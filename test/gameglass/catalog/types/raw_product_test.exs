defmodule Gameglass.Catalog.Types.RawProductTest do
  use ExUnit.Case, async: true

  alias Gameglass.Catalog.Types.RawProduct

  test "projects the catalog fields Gameglass uses" do
    payload = %{
      "ProductTitle" => "TUNIC",
      "XCloudTitleId" => "TUNIC",
      "XboxTitleId" => "1848191014",
      "XCloudOfferings" => %{"CLOUDGAMING" => %{"Programs" => ["DIA", "CALLISTO"]}},
      "PassMetadataByPassProductId" => %{"CFQ7TTC0P85B" => %{}},
      "Image_Tile" => %{"URL" => "//store-images.example/tunic.png"},
      "AnonymousPrice" => %{
        "MSRP" => %{
          "value" => 29.99,
          "formattedValue" => "$29.99",
          "currencyCode" => "USD"
        }
      },
      "UnusedUpstreamField" => "ignored"
    }

    product = RawProduct.from_json("9NLRT31Z4RWM", payload)

    assert product.product_id == "9NLRT31Z4RWM"
    assert product.title == "TUNIC"
    assert product.cloud_gaming?
    assert product.programs == ["DIA", "CALLISTO"]
    assert product.subscription_product_ids == ["CFQ7TTC0P85B"]
    assert product.price_value == 29.99
  end

  test "uses safe empty values when optional catalog sections are absent" do
    product = RawProduct.from_json("PRODUCT", %{"ProductTitle" => "Wrapper"})

    refute product.cloud_gaming?
    assert product.programs == []
    assert product.subscription_product_ids == []
    assert is_nil(product.price_value)
  end
end
