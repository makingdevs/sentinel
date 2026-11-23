defmodule Sentinel.VisitorCounting.Pipeline do
  @moduledoc "RTSP analytics ending at an RGB sink. No HLS, encoder or viewer lifetime."
  use Membrane.Pipeline
  alias Sentinel.Monitoring.RTSPSource
  def start(options), do: Membrane.Pipeline.start_link(__MODULE__, options)
  def stop(pid), do: Membrane.Pipeline.terminate(pid, force?: true, timeout: 2_000)

  @impl true
  def handle_init(_ctx, options), do: {[spec: RTSPSource.spec(options.source_url)], options}

  @impl true
  def handle_child_notification({:set_up_tracks, tracks}, :source, _ctx, state) do
    case RTSPSource.video_track(tracks) do
      nil ->
        send(state.owner, {:analytics_error, self(), :unsupported_codec})
        {[terminate: :normal], state}

      track ->
        encoding = String.upcase(track.rtpmap.encoding)
        parser = RTSPSource.parser(encoding)
        decoder = RTSPSource.decoder(encoding)

        spec =
          get_child(:source)
          |> via_out(Pad.ref(:output, track.control_path))
          |> via_in(:input, auto_demand_size: 1)
          |> child(:ingress, %Sentinel.VisitorCounting.MediaMeter{
            camera_id: state.rule.camera_id,
            channel: :secondary
          })
          |> via_in(:input, auto_demand_size: 1)
          |> child(:parser, parser)
          |> child(:decoder, decoder)
          |> via_in(:input, auto_demand_size: 1)
          |> child(:rgb, %Membrane.FFmpeg.SWScale.Converter{format: :RGB, output_width: 640})
          |> via_in(:input, auto_demand_size: 1)
          |> child(:latest, %Sentinel.Detection.LatestFrame{
            engine: state.rule.engine,
            generation: state.session
          })
          |> via_in(:input, auto_demand_size: 1)
          |> child(:detector, %Sentinel.Detection.Filter{
            engine: state.rule.engine,
            generation: state.session,
            counting_rule: state.rule
          })
          |> via_in(:input, auto_demand_size: 1)
          |> child(:discard, Sentinel.VisitorCounting.Discard)

        {[spec: spec], state}
    end
  end

  def handle_child_notification({:detection_status, status}, :detector, _ctx, state) do
    send(state.owner, {:analytics_status, self(), status})
    {[], state}
  end

  def handle_child_notification({:analytics_progress, crossings}, :detector, _ctx, state) do
    send(state.owner, {:analytics_progress, self(), crossings})
    {[], state}
  end

  def handle_child_notification(_, _, _, state), do: {[], state}

  @impl true
  def handle_element_end_of_stream(:discard, :input, _ctx, state),
    do: {[terminate: :normal], state}

  def handle_element_end_of_stream(_, _, _, state), do: {[], state}
end
