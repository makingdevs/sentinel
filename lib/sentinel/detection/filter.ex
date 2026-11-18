defmodule Sentinel.Detection.Filter do
  @moduledoc "Live RGB filter: bounded inference, latest-frame sampling and expiring boxes."
  use Membrane.Filter
  alias Sentinel.Detection

  def_input_pad(:input, accepted_format: %Membrane.RawVideo{pixel_format: :RGB})
  def_output_pad(:output, accepted_format: %Membrane.RawVideo{pixel_format: :RGB})
  def_options(engine: [spec: String.t()], generation: [spec: String.t()])

  @impl true
  def handle_init(_ctx, opts) do
    {[],
     %{
       engine: opts.engine,
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
  def handle_stream_format(:input, format, _ctx, state) do
    if format.width > 1280 or format.height > 1280 do
      raise ArgumentError, "detection frame exceeds 1280px bound"
    end

    {[stream_format: {:output, format}],
     %{state | format: format, objects: [], result_at: nil, result_pts: nil, pending: nil}}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    now = System.monotonic_time(:millisecond)
    id = state.sequence + 1

    frame = %{
      payload: buffer.payload,
      width: state.format.width,
      height: state.format.height,
      frame_id: id,
      pts: buffer.pts,
      captured_at: now,
      generation: state.generation
    }

    dropped = if state.busy != nil and state.pending != nil, do: 1, else: 0
    state = %{state | sequence: id}

    state =
      cond do
        not state.ready? ->
          state

        state.busy != nil ->
          %{state | pending: frame}

        due?(state, now) ->
          start_inference(state, frame)

        true ->
          state
      end

    max_age = Detection.get(:max_box_age_ms, 500)

    fresh? =
      state.result_at != nil and now - state.result_at <= max_age and
        is_integer(buffer.pts) and is_integer(state.result_pts) and
        buffer.pts >= state.result_pts and
        buffer.pts - state.result_pts <= Membrane.Time.milliseconds(max_age)

    objects = if fresh?, do: state.objects, else: []

    :telemetry.execute(
      [:sentinel, :detection, :frame],
      %{
        frames: 1,
        dropped: dropped,
        boxed: if(objects == [], do: 0, else: 1),
        box_age_ms: if(fresh?, do: now - state.result_at, else: 0),
        pts: buffer.pts
      },
      %{engine: state.engine, generation: state.generation}
    )

    buffer = %{buffer | metadata: Map.put(buffer.metadata, :detected_objects, objects)}

    status =
      if state.ready? and state.busy != nil and now - state.last_started > max_age,
        do: :saturated,
        else: state.status

    status = if status == :saturated and fresh?, do: :active, else: status

    actions =
      if status != state.status, do: [notify_parent: {:detection_status, status}], else: []

    {actions ++ [buffer: {:output, buffer}], %{state | status: status}}
  end

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

    objects =
      if state.inflight_format == {state.format.width, state.format.height},
        do: Detection.normalize(objects, state.format.width, state.format.height),
        else: []

    :telemetry.execute(
      [:sentinel, :detection, :inference],
      %{duration_us: elapsed, objects: length(objects)},
      %{engine: state.engine, generation: state.generation}
    )

    state = %{
      state
      | objects: objects,
        result_at: captured,
        result_pts: pts,
        busy: nil,
        timer: nil,
        retry_count: 0
    }

    state =
      if state.pending != nil and
           due?(state, System.monotonic_time(:millisecond)) do
        start_inference(%{state | pending: nil}, state.pending)
      else
        %{state | pending: nil}
      end

    {[], state}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, _ctx, %{monitor: ref} = state) do
    if state.timer, do: Process.cancel_timer(state.timer)

    state = %{
      state
      | ready?: false,
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
    if state.worker,
      do: DynamicSupervisor.terminate_child(Sentinel.Detection.Supervisor, state.worker)

    {[notify_parent: {:detection_status, :error}],
     %{state | ready?: false, busy: nil, pending: nil, objects: []}}
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
        inflight_format: {frame.width, frame.height},
        last_started: System.monotonic_time(:millisecond),
        timer: timer
    }
  end
end
