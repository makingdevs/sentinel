defmodule Sentinel.MonitoringTest do
  use ExUnit.Case, async: false

  alias Sentinel.Monitoring

  setup do
    original = Monitoring.config()

    Application.put_env(
      :sentinel,
      :monitoring,
      Keyword.put(original, :sources, %{
        "division-1" => %{"secundaria" => "rtsp://user:secret@127.0.0.1:8554/private"}
      })
    )

    on_exit(fn -> Application.put_env(:sentinel, :monitoring, original) end)
    :ok
  end

  test "eight physical cameras have grouped options and same-origin HLS URLs" do
    cameras = Monitoring.list_cameras()
    assert length(cameras) == 8
    assert length(Enum.uniq_by(cameras, & &1.id)) == 8

    assert Enum.map(Monitoring.camera_options(), fn {branch, options} ->
             {branch, length(options)}
           end) ==
             [{"División", 4}, {"La Virgen", 4}]

    for camera <- cameras, quality <- ~w(principal secundaria) do
      assert {:ok, "/hls/" <> _path = url} = Monitoring.player_url(camera.id, quality)
      assert url == "/hls/#{camera.id}/#{quality}/index.m3u8"
      refute url =~ "rtsp"
      refute url =~ "secret"
    end
  end

  test "rejects IDs and qualities outside the catalog" do
    for id <- ["missing", "../private", "https://evil.example", nil, %{}] do
      assert {:error, :unknown_camera} = Monitoring.player_url(id, "secundaria")
    end

    for quality <- ["other", "../principal", nil, :principal, %{}] do
      assert {:error, :unknown_quality} = Monitoring.player_url("division-1", quality)
    end
  end

  test "private RTSP URLs are separate from public URLs" do
    assert {:ok, "rtsp://user:secret@127.0.0.1:8554/private"} =
             Monitoring.source_url("division-1", "secundaria")

    assert {:error, :source_not_configured} = Monitoring.source_url("division-1", "principal")
    config = Monitoring.config()

    for source <- ["file:///etc/passwd", "http://example.com", "rtsp:///missing-host"] do
      Application.put_env(
        :sentinel,
        :monitoring,
        Keyword.put(config, :sources, %{"division-1" => %{"secundaria" => source}})
      )

      assert {:error, :invalid_source} = Monitoring.source_url("division-1", "secundaria")
    end
  end

  test "rejects unsafe filenames before opening a source" do
    for filename <- [
          "../secret.mp4",
          "file.mp4/other",
          ".env",
          "file.pending",
          "index.m3u8?x=1",
          nil
        ] do
      assert {:error, :invalid_filename} =
               Monitoring.media_file("division-1", "secundaria", filename)
    end

    assert {:error, :unknown_camera} =
             Monitoring.media_file("missing", "secundaria", "index.m3u8")
  end
end
