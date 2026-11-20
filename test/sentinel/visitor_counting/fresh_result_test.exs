defmodule Sentinel.VisitorCounting.FreshResultTest do
  use Sentinel.DataCase, async: false
  alias Sentinel.Detection.Filter
  alias Sentinel.VisitorCounting.{Rule, Writer}

  for primary? <- [false, true] do
    test "one crossing preserves exact secondary inference frame with primary=#{primary?}" do
      primary? = unquote(primary?)
      if primary?, do: start_primary()

      previous = Application.get_env(:sentinel, :visitor_counting, [])
      root = "/private/tmp/visitor-fresh-#{System.unique_integer([:positive])}"
      Application.put_env(:sentinel, :visitor_counting, snapshot_root: root)

      on_exit(fn ->
        Application.put_env(:sentinel, :visitor_counting, previous)
        File.rm_rf!(root)
      end)

      Phoenix.PubSub.subscribe(Sentinel.PubSub, "visitor_events")

      {[], state} =
        Filter.handle_init(%{}, %Filter{
          engine: "python",
          generation: "fresh",
          counting_rule: %Rule{camera_id: "division-1"}
        })

      format = %Membrane.RawVideo{
        width: 160,
        height: 100,
        framerate: {25, 1},
        pixel_format: :RGB,
        aligned: true
      }

      {_, state} = Filter.handle_stream_format(:input, format, %{}, state)
      :sys.suspend(Writer)

      try do
        state =
          Enum.reduce(Enum.with_index([0.3, 0.35, 0.4, 0.45, 0.55], 1), state, fn {y, i}, state ->
            buffer = %Membrane.Buffer{
              payload: :binary.copy(<<i, 0, 0>>, 160 * 100),
              pts: Membrane.Time.milliseconds(i * 200)
            }

            {_, state} =
              Filter.handle_buffer(:input, buffer, %{}, %{
                state
                | worker: self(),
                  ready?: true,
                  last_started: nil
              })

            assert_receive {:infer, frame}
            assert frame.payload == :binary.copy(<<i, 0, 0>>, 160 * 100)
            assert frame.width == 160
            assert frame.height == 100

            objects = [
              %{"class_id" => 0, "confidence" => 0.9, "xyxy" => [64, y * 100 - 30, 96, y * 100]}
            ]

            {_, state} =
              Filter.handle_info(
                {:detector_result, self(), i, frame.pts, frame.captured_at, {:ok, objects}, 10},
                %{},
                state
              )

            state
          end)

        assert Writer.stats("division-1").queued == 1
        [{_, _, event, _, _}] = :ets.match_object(Writer, {{:job, :_}, :_, :_, :_, :_})

        if primary? do
          refute Map.has_key?(event, :frame)
          assert event.attrs.snapshot_quality == "primary"
          assert event.attrs.tracking_width == 160
          assert event.attrs.snapshot_width == 800
        else
          assert event.frame.frame_id == 5
          assert event.frame.payload == :binary.copy(<<5, 0, 0>>, 160 * 100)
          assert event.attrs.snapshot_quality == "secondary"
        end

        buffer = %Membrane.Buffer{
          payload: :binary.copy(<<99, 0, 0>>, 160 * 100),
          pts: state.result_pts
        }

        Filter.handle_buffer(:input, buffer, %{}, state)
        assert Writer.stats("division-1").queued == 1
      after
        :sys.resume(Writer)
      end

      assert_receive {:passage_saved, id}, 5_000
      event = Sentinel.VisitorCounting.get_event(id)
      {:ok, path} = Sentinel.VisitorCounting.Snapshots.path(event.snapshot_key)
      image = Image.open!(path)
      assert Image.width(image) == if(primary?, do: 800, else: 160)
      assert Image.height(image) == if(primary?, do: 480, else: 100)

      if primary? do
        assert {:ok, [r, g, b]} = Image.get_pixel(image, 0, 0)
        assert g > r + 100 and g > b + 100
      end

      :sys.get_state(Writer)
    end
  end

  defp start_primary do
    import Sentinel.MonitoringFixtures
    camera_catalog_fixture()
    camera_source_fixture("division-1", "principal", "rtsp://example.test/primary")
    Application.put_env(:sentinel, :media_test_owner, self())
    on_exit(fn -> Application.delete_env(:sentinel, :media_test_owner) end)

    start_supervised!(
      {DynamicSupervisor, name: Sentinel.TestMediaSupervisor, strategy: :one_for_one}
    )

    source =
      start_supervised!(
        {Sentinel.VisitorCounting.SnapshotSource,
         camera_id: "division-1", owner: self(), runner: Sentinel.TestMediaPipeline}
      )

    assert_receive {:media_started, _, _}
    {:ok, jpeg} = Image.new!(800, 480, color: [0, 220, 0]) |> Image.write(:memory, suffix: ".jpg")
    gen = Sentinel.VisitorCounting.SnapshotSource.generation("division-1")

    :ok =
      Sentinel.VisitorCounting.SnapshotSource.put(source, gen, %{
        jpeg: jpeg,
        width: 800,
        height: 480,
        received_mono: System.monotonic_time(:millisecond),
        received_at: DateTime.utc_now()
      })
  end
end
