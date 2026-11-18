defmodule Sentinel.VisitorCounting.FreshResultTest do
  use Sentinel.DataCase, async: false
  alias Sentinel.Detection.Filter
  alias Sentinel.VisitorCounting.{Rule, Writer}

  test "one crossing admits exactly the inferred frame, never replayed overlay boxes" do
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
      assert event.frame.frame_id == 5
      assert event.frame.payload == :binary.copy(<<5, 0, 0>>, 160 * 100)

      buffer = %Membrane.Buffer{
        payload: :binary.copy(<<99, 0, 0>>, 160 * 100),
        pts: state.result_pts
      }

      Filter.handle_buffer(:input, buffer, %{}, state)
      assert Writer.stats("division-1").queued == 1
    after
      :sys.resume(Writer)
    end

    assert_receive {:passage_saved, _id}, 5_000
    :sys.get_state(Writer)
  end
end
