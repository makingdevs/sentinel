defmodule SentinelWeb.HlsControllerTest do
  use SentinelWeb.ConnCase, async: false

  alias Sentinel.Monitoring

  setup do
    original = Monitoring.config()

    directory =
      Path.join(System.tmp_dir!(), "sentinel-hls-http-#{System.unique_integer([:positive])}")

    start_supervised!(
      {DynamicSupervisor, name: Sentinel.TestMediaSupervisor, strategy: :one_for_one}
    )

    Application.put_env(:sentinel, :media_test_owner, self())

    Application.put_env(
      :sentinel,
      :monitoring,
      Keyword.merge(original,
        hls_directory: directory,
        pipeline_module: Sentinel.TestMediaPipeline,
        sources: %{"division-1" => %{"secundaria" => "rtsp://user:secret@example.test/private"}}
      )
    )

    on_exit(fn ->
      for {pid, _} <- Registry.lookup(Sentinel.Monitoring.Registry, {"division-1", "secundaria"}) do
        DynamicSupervisor.terminate_child(Sentinel.Monitoring.Supervisor, pid)
      end

      Application.put_env(:sentinel, :monitoring, original)
      Application.delete_env(:sentinel, :media_test_owner)
      File.rm_rf!(directory)
    end)

    :ok
  end

  test "returns a retryable response while warming up, without source details", %{conn: conn} do
    conn = get(conn, "/hls/division-1/secundaria/index.m3u8")
    body = response(conn, 503)
    assert get_resp_header(conn, "retry-after") == ["3"]
    refute body =~ "secret"
    refute body =~ "rtsp"
  end

  test "serves manifests and fragments with correct types and no stale caching", %{conn: conn} do
    assert {:error, :warming_up} = Monitoring.media_file("division-1", "secundaria", "index.m3u8")
    assert_receive {:media_started, media, options}

    for {name, body} <- [
          {"index.m3u8", "#EXTM3U\n"},
          {"video.m4s", <<1, 2, 3>>},
          {"header.mp4", <<4, 5, 6>>}
        ] do
      File.write!(Path.join(options.directory, name), body)
    end

    send(options.owner, {:pipeline_ready, media})
    _ = :sys.get_state(options.owner)

    for {name, type} <- [
          {"index.m3u8", "application/vnd.apple.mpegurl"},
          {"video.m4s", "video/iso.segment"},
          {"header.mp4", "video/mp4"}
        ] do
      response_conn = get(conn, "/hls/division-1/secundaria/#{name}")
      assert response_conn.status == 200
      assert hd(get_resp_header(response_conn, "content-type")) =~ type
      assert get_resp_header(response_conn, "cache-control") == ["no-store"]
    end

    assert get(conn, "/hls/division-1/secundaria/missing.m4s").status == 404
  end

  test "unknown cameras, qualities and extensions cannot access files", %{conn: conn} do
    for path <- [
          "/hls/missing/secundaria/index.m3u8",
          "/hls/division-1/invalid/index.m3u8",
          "/hls/division-1/secundaria/private.txt"
        ] do
      assert get(conn, path).status == 404
    end

    assert get(conn, "/hls/division-1/principal/index.m3u8").status == 503
    refute_received {:media_started, _, _}
  end
end
