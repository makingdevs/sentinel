defmodule Sentinel.MonitoringStorageTest do
  use ExUnit.Case, async: true

  alias Sentinel.Monitoring.FileStorage

  @tag :tmp_dir
  test "publishes complete files atomically and removes stale segments", %{tmp_dir: directory} do
    state = FileStorage.init(%FileStorage{directory: directory})

    assert {:ok, ^state} =
             FileStorage.store(
               :master,
               "index.m3u8",
               "#EXTM3U\n",
               %{},
               %{mode: :text, type: :manifest},
               state
             )

    assert File.read!(Path.join(directory, "index.m3u8")) == "#EXTM3U\n"
    refute File.exists?(Path.join(directory, "index.m3u8.pending"))
    assert {:ok, ^state} = FileStorage.remove(:master, "index.m3u8", %{}, state)
    assert {:ok, ^state} = FileStorage.remove(:master, "index.m3u8", %{}, state)
    refute File.exists?(Path.join(directory, "index.m3u8"))
  end
end
