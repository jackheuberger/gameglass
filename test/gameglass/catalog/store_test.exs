defmodule Gameglass.Catalog.StoreTest do
  use ExUnit.Case, async: true

  alias Gameglass.Catalog.{Mapper, Store}
  alias Gameglass.Catalog.Types.{RawProduct, Run}

  @moduletag :tmp_dir

  @programs ~w(GPULTIMATE CALLISTO DIA EUROPA TRITON)
  @premium "CFQ7TTC0P85B"

  defp rec(product_id, xcloud_title_id, opts \\ []) do
    raw = %{
      "ProductTitle" => Keyword.get(opts, :title, product_id),
      "XCloudTitleId" => xcloud_title_id,
      "XCloudOfferings" => %{
        "CLOUDGAMING" => %{"Programs" => Keyword.get(opts, :programs, @programs)}
      },
      "PassMetadataByPassProductId" =>
        Map.new(Keyword.get(opts, :subscription_ids, [@premium]), &{&1, %{}}),
      "AnonymousPrice" => %{
        "MSRP" => %{
          "value" => Keyword.get(opts, :price, 9.99),
          "formattedValue" => Keyword.get(opts, :price_formatted, "$9.99")
        }
      }
    }

    product_id
    |> RawProduct.from_json(raw)
    |> Mapper.normalize()
  end

  defp enumerated_product_ids(scanned_games) do
    MapSet.new(scanned_games, & &1.base_product_id)
  end

  defp commit(dir, scanned_games) do
    Store.commit(dir, scanned_games, enumerated_product_ids(scanned_games))
  end

  defp game(dir, xcloud_title_id) do
    Enum.find(Store.load_games(dir), &(&1.xcloud_title_id == xcloud_title_id))
  end

  test "first run is the baseline: added_at stays nil and a success run is recorded",
       %{tmp_dir: dir} do
    {:ok, summary} = commit(dir, [rec("A", "GAMEA"), rec("B", "GAMEB")])

    assert summary.added == 2
    assert Store.load_games(dir) |> Enum.all?(&is_nil(&1.added_at))

    assert %Run{status: :success, added: 2, finished_at: finished} = Store.last_run(dir)
    refute is_nil(finished)
  end

  test "additions after the baseline get a genuine added_at", %{tmp_dir: dir} do
    {:ok, _} = commit(dir, [rec("A", "GAMEA")])
    {:ok, summary} = commit(dir, [rec("A", "GAMEA"), rec("B", "GAMEB")])

    assert summary.added == 1
    refute is_nil(game(dir, "GAMEB").added_at)
    # the baseline game keeps nil ("tracked since launch")
    assert is_nil(game(dir, "GAMEA").added_at)
  end

  test "removal sets removed_at and flips streamable", %{tmp_dir: dir} do
    {:ok, _} = commit(dir, [rec("A", "GAMEA"), rec("B", "GAMEB")])
    {:ok, summary} = commit(dir, [rec("A", "GAMEA")])

    assert summary.removed == 1
    b = game(dir, "GAMEB")
    refute b.streamable
    refute is_nil(b.removed_at)
  end

  test "re-add resets added_at, clears removed_at, and emits game_added", %{tmp_dir: dir} do
    {:ok, _} = commit(dir, [rec("A", "GAMEA"), rec("B", "GAMEB")])
    {:ok, _} = commit(dir, [rec("A", "GAMEA")])
    {:ok, summary} = commit(dir, [rec("A", "GAMEA"), rec("B", "GAMEB")])

    assert summary.added == 1
    b = game(dir, "GAMEB")
    assert b.streamable
    assert is_nil(b.removed_at)
    refute is_nil(b.added_at)

    assert Enum.any?(
             Store.load_changes(dir),
             &(&1.kind == :game_added and &1.xcloud_title_id == "GAMEB")
           )
  end

  test "tier status and price changes are logged and stamp last_changed_at", %{tmp_dir: dir} do
    {:ok, _} = commit(dir, [rec("A", "GAMEA", subscription_ids: [@premium])])
    verified = game(dir, "GAMEA")

    {:ok, summary} =
      commit(dir, [
        rec("A", "GAMEA", subscription_ids: [], price: 4.99, price_formatted: "$4.99")
      ])

    assert summary.changed > 0

    changes = Store.load_changes(dir)

    assert Enum.any?(changes, fn event ->
             event.kind == :tier_status_changed and is_atom(event.old_value) and
               is_atom(event.new_value)
           end)

    assert Enum.any?(
             changes,
             &(&1.kind == :price_changed and &1.old_value == "$9.99" and
                 &1.new_value == "$4.99")
           )

    assert game(dir, "GAMEA").last_changed_at >= verified.last_changed_at
  end

  test "change events are linked to their run", %{tmp_dir: dir} do
    {:ok, _} = commit(dir, [rec("A", "GAMEA")])

    run = Store.last_run(dir)
    events = Store.load_changes(dir)
    assert events != []
    assert Enum.all?(events, &(&1.run_id == run.id))
  end

  test "a failing reconcile records a failed run and reraises", %{tmp_dir: dir} do
    bad = [%{market: "US"}]

    assert_raise KeyError, fn ->
      Store.commit(dir, bad, MapSet.new())
    end

    assert %Run{status: :failed, error: error} = Store.last_run(dir)
    refute is_nil(error)
  end

  test "a game the enumeration still lists but enrichment missed is not marked removed",
       %{tmp_dir: dir} do
    {:ok, _} = commit(dir, [rec("A", "GAMEA"), rec("B", "GAMEB")])

    # B's product id was enumerated but its enrichment batch failed.
    {:ok, summary} = Store.commit(dir, [rec("A", "GAMEA")], MapSet.new(["A", "B"]))

    assert summary.removed == 0
    assert game(dir, "GAMEB").streamable
  end
end
