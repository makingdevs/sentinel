defmodule Sentinel.Detection.Filter do
  @moduledoc "Live RGB filter: bounded inference, latest-frame sampling and expiring boxes."
  use Membrane.Filter
  alias Sentinel.Detection

  def_input_pad(:input, accepted_format: %Membrane.RawVideo{pixel_format: :RGB})
  def_output_pad(:output, accepted_format: %Membrane.RawVideo{pixel_format: :RGB})

  def_options(
    engine: [spec: String.t()],
    generation: [spec: String.t()],
    counting_rule: [spec: term(), default: nil]
  )

  @impl true
  def handle_init(_ctx, opts) do
    {[],
     %{
       engine: opts.engine,
       counting_rule: opts.counting_rule,
       tracker: Sentinel.VisitorCounting.Tracker.new(),
       tracking_session: Ecto.UUID.generate(),
       inflight_frame: nil,
       generation: opts.generation,
       worker: nil,
       monitor: nil,
       ready?: false,
       status: :loading,
       busy: nil,
       inflight_format: nil,
       timer: nil,
       pending: nil,
       sequence: 0,
       last_started: nil,
       retry_count: 0,
       objects: [],
       result_at: nil,
       result_pts: nil,
       format: nil
     }}
  end

  @impl true
  def handle_setup(_ctx, state) do
    case DynamicSupervisor.start_child(
           Sentinel.Detection.Supervisor,
           {Sentinel.Detection.Worker, owner: self(), engine: state.engine}
         ) do
      {:ok, worker} ->
        timer = Process.send_after(self(), {:load_timeout, worker}, 120_000)

        {[notify_parent: {:detection_status, :loading}],
         %{state | worker: worker, monitor: Process.monitor(worker), timer: timer}}

      {:error, _} ->
        {[notify_parent: {:detection_status, :capacity}], retry_later(state)}
    end
  end

  @impl true
  def handle_stream_format(:input, %{width: width, height: height}, _ctx, _state)
      when width > 1280 or height > 1280 do
    raise ArgumentError, "detection frame exceeds 1280px bound"
  end

  def handle_stream_format(:input, format, _ctx, state) do
    {[stream_format: {:output, format}],
     %{
       state
       | format: format,
         objects: [],
         result_at: nil,
         result_pts: nil,
         pending: nil,
         tracker: Sentinel.VisitorCounting.Tracker.new(),
         tracking_session: Ecto.UUID.generate()
     }}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    now = System.monotonic_time(:millisecond)
    frame = build_frame(buffer, state, now)
    dropped = dropped_frame(state)
    state = state |> Map.put(:sequence, frame.frame_id) |> schedule_inference(frame, now)
    max_age = Detection.get(:max_box_age_ms, 500)
    fresh? = fresh_result?(state, buffer.pts, now, max_age)
    {objects, age} = visible_result(state, fresh?, now)

    :telemetry.execute(
      [:sentinel, :detection, :frame],
      %{frames: 1, dropped: dropped, boxed: boxed(objects), box_age_ms: age, pts: buffer.pts},
      %{engine: state.engine, generation: state.generation}
    )

    buffer = %{buffer | metadata: Map.put(buffer.metadata, :detected_objects, objects)}
    status = state |> frame_status(now, max_age) |> recover_status(fresh?)

    {status_actions(state.status, status) ++ [buffer: {:output, buffer}],
     %{state | status: status}}
  end

  defp build_frame(buffer, state, now) do
    %{
      payload: buffer.payload,
      width: state.format.width,
      height: state.format.height,
      frame_id: state.sequence + 1,
      pts: buffer.pts,
      captured_at: now,
      snapshot_generation: snapshot_generation(state.counting_rule),
      generation: state.generation,
      crossed_at: DateTime.utc_now()
    }
  end

  defp snapshot_generation(nil), do: nil

  defp snapshot_generation(rule),
    do: Sentinel.VisitorCounting.SnapshotSource.generation(rule.camera_id)

  defp dropped_frame(%{busy: busy, pending: pending})
       when not is_nil(busy) and not is_nil(pending), do: 1

  defp dropped_frame(_state), do: 0

  defp schedule_inference(%{ready?: false} = state, _frame, _now), do: state

  defp schedule_inference(%{busy: busy} = state, frame, _now) when not is_nil(busy),
    do: %{state | pending: frame}

  defp schedule_inference(state, frame, now) do
    case due?(state, now) do
      true -> start_inference(state, frame)
      false -> state
    end
  end

  defp fresh_result?(%{result_at: nil}, _pts, _now, _max_age), do: false

  defp fresh_result?(state, pts, now, max_age)
       when is_integer(pts) and is_integer(state.result_pts) do
    now - state.result_at <= max_age and pts >= state.result_pts and
      pts - state.result_pts <= Membrane.Time.milliseconds(max_age)
  end

  defp fresh_result?(_state, _pts, _now, _max_age), do: false

  defp visible_result(state, true, now), do: {state.objects, now - state.result_at}
  defp visible_result(_state, false, _now), do: {[], 0}
  defp boxed([]), do: 0
  defp boxed(_objects), do: 1

  defp frame_status(%{ready?: true, busy: busy, last_started: started}, now, max_age)
       when not is_nil(busy) and now - started > max_age, do: :saturated

  defp frame_status(state, _now, _max_age), do: state.status
  defp recover_status(:saturated, true), do: :active
  defp recover_status(status, _fresh?), do: status
  defp status_actions(status, status), do: []
  defp status_actions(_previous, status), do: [notify_parent: {:detection_status, status}]

  @impl true
  def handle_info({:detector_ready, worker}, _ctx, %{worker: worker} = state) do
    Process.cancel_timer(state.timer)

    {[notify_parent: {:detection_status, :active}],
     %{state | ready?: true, timer: nil, status: :active}}
  end

  def handle_info(
        {:detector_result, worker, id, pts, captured, {:ok, objects}, elapsed},
        _ctx,
        %{worker: worker, busy: id} = state
      ) do
    Process.cancel_timer(state.timer)

    objects = normalize_result(objects, state)

    :telemetry.execute(
      [:sentinel, :detection, :inference],
      %{duration_us: elapsed, objects: length(objects)},
      %{engine: state.engine, generation: state.generation}
    )

    {crossing_actions, state} = count_result(objects, state)

    state = %{
      state
      | objects: objects,
        result_at: captured,
        result_pts: pts,
        busy: nil,
        inflight_frame: nil,
        timer: nil,
        retry_count: 0
    }

    state = resume_pending(state)

    {crossing_actions, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, _ctx, %{monitor: ref} = state) do
    cancel_timer(state.timer)

    state = %{
      state
      | ready?: false,
        tracker: Sentinel.VisitorCounting.Tracker.new(),
        tracking_session: Ecto.UUID.generate(),
        inflight_frame: nil,
        worker: nil,
        busy: nil,
        pending: nil,
        objects: [],
        timer: nil
    }

    {[notify_parent: {:detection_status, :error}], retry_later(state)}
  end

  def handle_info({:inference_timeout, id}, ctx, %{busy: id} = state) when not is_nil(id),
    do: timeout(ctx, state)

  def handle_info({:load_timeout, worker}, ctx, %{worker: worker, ready?: false} = state),
    do: timeout(ctx, state)

  def handle_info(
        {:retry_detector, generation},
        ctx,
        %{worker: nil, generation: generation} = state
      ),
      do: handle_setup(ctx, state)

  def handle_info(_old_result, _ctx, state), do: {[], state}

  @impl true
  def handle_parent_notification(:retry_detector, ctx, %{worker: nil} = state),
    do: handle_setup(ctx, %{state | retry_count: 0})

  def handle_parent_notification(_notification, _ctx, state), do: {[], state}

  defp retry_later(%{retry_count: count} = state) when count < 3 do
    Process.send_after(self(), {:retry_detector, state.generation}, 1_000 * Integer.pow(2, count))
    %{state | retry_count: count + 1}
  end

  defp retry_later(state), do: state

  defp timeout(_ctx, state) do
    stop_worker(state.worker)

    {[notify_parent: {:detection_status, :error}],
     %{
       state
       | ready?: false,
         busy: nil,
         pending: nil,
         objects: [],
         inflight_frame: nil,
         tracker: Sentinel.VisitorCounting.Tracker.new(),
         tracking_session: Ecto.UUID.generate()
     }}
  end

  defp due?(%{last_started: nil}, _now), do: true
  defp due?(state, now), do: now - state.last_started >= Detection.get(:interval_ms, 200)

  defp start_inference(state, frame) do
    send(state.worker, {:infer, frame})

    timer =
      Process.send_after(
        self(),
        {:inference_timeout, frame.frame_id},
        Detection.get(:timeout_ms, 10_000)
      )

    %{
      state
      | busy: frame.frame_id,
        inflight_frame: counting_frame(state.counting_rule, frame),
        inflight_format: {frame.width, frame.height},
        last_started: System.monotonic_time(:millisecond),
        timer: timer
    }
  end

  defp counting_frame(nil, _frame), do: nil
  defp counting_frame(_rule, frame), do: frame
  defp cancel_timer(nil), do: nil
  defp cancel_timer(timer), do: Process.cancel_timer(timer)
  defp stop_worker(nil), do: nil

  defp stop_worker(worker),
    do: DynamicSupervisor.terminate_child(Sentinel.Detection.Supervisor, worker)

  defp normalize_result(objects, %{
         inflight_format: {width, height},
         format: %{width: width, height: height}
       }),
       do: Detection.normalize(objects, width, height)

  defp normalize_result(_objects, _state), do: []

  defp count_result(_objects, %{counting_rule: nil} = state), do: {[], state}

  defp count_result(
         objects,
         %{inflight_format: {width, height}, format: %{width: width, height: height}} = state
       ) do
    {tracker, events} =
      Sentinel.VisitorCounting.Processor.process(
        state.tracker,
        objects,
        state.inflight_frame,
        state.counting_rule,
        state.tracking_session
      )

    Enum.each(events, &Sentinel.VisitorCounting.Writer.enqueue/1)
    {[notify_parent: {:analytics_progress, length(events)}], %{state | tracker: tracker}}
  end

  defp count_result(_objects, state), do: {[], state}

  defp resume_pending(%{pending: nil} = state), do: state

  defp resume_pending(%{pending: frame} = state) do
    state = %{state | pending: nil}

    case due?(state, System.monotonic_time(:millisecond)) do
      true -> start_inference(state, frame)
      false -> state
    end
  end
end
