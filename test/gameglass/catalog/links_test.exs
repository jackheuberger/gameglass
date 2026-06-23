defmodule Gameglass.Catalog.LinksTest do
  use ExUnit.Case, async: true

  alias Gameglass.Catalog.Links

  test "builds the three product URLs" do
    assert Links.store("9NLRT31Z4RWM", "TUNIC") ==
             "https://www.xbox.com/games/store/tunic/9NLRT31Z4RWM"

    assert Links.play_legacy("9NLRT31Z4RWM", "TUNIC") ==
             "https://www.xbox.com/play/games/tunic/9NLRT31Z4RWM"

    assert Links.play_new("9NLRT31Z4RWM", "TUNIC") ==
             "https://play.xbox.com/products/9NLRT31Z4RWM/tunic"
  end

  test "slugifies titles with punctuation and trademark symbols" do
    assert Links.slug("EA SPORTS FC™ 25") == "ea-sports-fc-25"
    assert Links.slug("Ori and the Will of the Wisps") == "ori-and-the-will-of-the-wisps"
    assert Links.slug("Halo: The Master Chief Collection") == "halo-the-master-chief-collection"
  end

  test "falls back to a placeholder when title is missing or empty" do
    assert Links.slug(nil) == "_"
    assert Links.slug("") == "_"
    assert Links.slug("™™™") == "_"
    assert Links.store("ABC123", nil) == "https://www.xbox.com/games/store/_/ABC123"
  end
end
