defmodule Sentinel.VisitorCounting.SnapshotDecodeTest do
  use Sentinel.DataCase, async: false
  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions
  import Sentinel.MonitoringFixtures
  alias Sentinel.VisitorCounting.SnapshotSource

  setup do
    camera_catalog_fixture()
    camera_source_fixture("division-1", "principal", "rtsp://example.test/primary")
    Application.put_env(:sentinel, :media_test_owner, self())
    on_exit(fn -> Application.delete_env(:sentinel, :media_test_owner) end)

    start_supervised!(
      {DynamicSupervisor, name: Sentinel.TestMediaSupervisor, strategy: :one_for_one}
    )

    source =
      start_supervised!(
        {SnapshotSource,
         camera_id: "division-1", owner: self(), runner: Sentinel.TestMediaPipeline}
      )

    assert_receive {:media_started, _, options}
    %{source: source, generation: options.generation}
  end

  for codec <- [:h264, :h265] do
    @tag timeout: 30_000
    test "real #{codec} native decoder preserves larger primary dimensions", ctx do
      codec = unquote(codec)

      {encoder, decoder} = codec_modules(codec)

      format = %Membrane.RawVideo{
        width: 960,
        height: 540,
        pixel_format: :I420,
        framerate: {25, 1},
        aligned: true
      }

      payload = :binary.copy(<<100>>, 960 * 540) <> :binary.copy(<<128>>, div(960 * 540, 2))

      buffers =
        for n <- 0..3,
            do: %Membrane.Buffer{payload: payload, pts: n * Membrane.Time.milliseconds(40)}

      spec =
        child(:fixture, %Membrane.Testing.Source{stream_format: format, output: buffers})
        |> child(:encoder, encoder)
        |> child(:decoder, decoder)
        |> via_in(:input, auto_demand_size: 1)
        |> child(:sampler, Sentinel.VisitorCounting.SnapshotSampler)
        |> via_in(:input, auto_demand_size: 1)
        |> child(:rgb, %Membrane.FFmpeg.SWScale.Converter{format: :RGB})
        |> via_in(:input, target_queue_size: 1, min_demand_factor: 1)
        |> child(:jpeg, %Sentinel.VisitorCounting.SnapshotSink{
          source: ctx.source,
          generation: ctx.generation
        })

      pipeline = Membrane.Testing.Pipeline.start_link_supervised!(spec: spec)
      assert_end_of_stream(pipeline, :jpeg, :input, 15_000)
      assert {:ok, %{frames: [frame | _]}} = SnapshotSource.read("division-1")
      assert frame.width == 960
      assert frame.height == 540
      assert {:ok, image} = Image.from_binary(frame.jpeg)
      assert Image.width(image) == 960
      assert Image.height(image) == 540
    end
  end

  defp codec_modules(:h264),
    do:
      {%Membrane.H264.FFmpeg.Encoder{preset: :ultrafast, tune: :zerolatency},
       Membrane.H264.FFmpeg.Decoder}

  defp codec_modules(:h265),
    do:
      {%Membrane.H265.FFmpeg.Encoder{preset: :ultrafast, tune: :zerolatency},
       Membrane.H265.FFmpeg.Decoder}
end
