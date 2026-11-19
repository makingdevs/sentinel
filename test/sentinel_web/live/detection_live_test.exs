defmodule SentinelWeb.DetectionLiveTest do
  use SentinelWeb.ConnCase, async: false
  import Sentinel.MonitoringFixtures
  setup :camera_catalog_fixture_setup

  defp camera_catalog_fixture_setup(_context), do: camera_catalog_fixture()

  import Phoenix.LiveViewTest

  setup do
    previous = Application.get_env(:sentinel, :detection, [])

    directory =
      Path.join(System.tmp_dir!(), "detector-models-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)

    for extension <- ~w(pt onnx),
        do: File.write!(Path.join(directory, "yolo11n.#{extension}"), "test")

    Application.put_env(:sentinel, :detection, model_directory: directory, python: __ENV__.file)

    on_exit(fn ->
      Application.put_env(:sentinel, :detection, previous)
      File.rm_rf!(directory)
    end)

    :ok
  end

  test "engine switching isolates a camera and retains its engine across quality changes", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, ~p"/cameras")

    for id <- ~w(division-1 lavirgen-1),
        do: view |> form("#camera-selection-form", selection: %{camera_id: id}) |> render_submit()

    view |> form("#detection-division-1", detection: %{engine: "python"}) |> render_change()

    assert has_element?(
             view,
             "#player-division-1-secundaria-1[data-source='/hls/division-1/secundaria/python/index.m3u8']"
           )

    assert has_element?(view, "#player-lavirgen-1-secundaria-0")
    view |> form("#quality-division-1", quality: %{value: "principal"}) |> render_change()

    assert has_element?(
             view,
             "#player-division-1-principal-2[data-source='/hls/division-1/principal/python/index.m3u8']"
           )

    view |> form("#detection-division-1", detection: %{engine: "elixir"}) |> render_change()

    assert has_element?(
             view,
             "#player-division-1-principal-3[data-source='/hls/division-1/principal/elixir/index.m3u8']"
           )

    view |> form("#detection-division-1", detection: %{engine: "off"}) |> render_change()

    assert has_element?(
             view,
             "#player-division-1-principal-4[data-source='/hls/division-1/principal/index.m3u8']"
           )

    refute has_element?(view, "#player-division-1-principal-4 [data-detection-status]")
  end

  test "malicious engine input leaves the player unchanged", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/cameras")

    view
    |> form("#camera-selection-form", selection: %{camera_id: "division-1"})
    |> render_submit()

    render_change(view, "engine", %{
      "id" => "division-1",
      "detection" => %{"engine" => "../../tmp"}
    })

    assert has_element?(view, "#flash-error")
    assert has_element?(view, "#player-division-1-secundaria-0")
  end
end
