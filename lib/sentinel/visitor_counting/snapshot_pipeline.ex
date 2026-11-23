defmodule Sentinel.VisitorCounting.SnapshotPipeline do
  @moduledoc "Independent native primary decode path; no HLS, detector, tracker or scaling."
  use Membrane.Pipeline
  alias Sentinel.Monitoring.RTSPSource
  def start(opts), do: Membrane.Pipeline.start_link(__MODULE__, opts)
  def stop(pid), do: Membrane.Pipeline.terminate(pid, force?: true, timeout: 2_000)
  @impl true
  def handle_init(_ctx, options), do: {[spec: RTSPSource.spec(options.source_url)], options}

  @impl true
  def handle_child_notification({:set_up_tracks, tracks}, :source, _, state) do
    case RTSPSource.video_track(tracks) do
      nil ->
        {[terminate: :normal], state}

      track ->
        encoding = String.upcase(track.rtpmap.encoding)
        parser = RTSPSource.parser(encoding)
        decoder = RTSPSource.decoder(encoding)

        spec =
          get_child(:source)
          |> via_out(Pad.ref(:output, track.control_path))
          |> via_in(:input, auto_demand_size: 1, toilet_capacity: 64)
          |> child(:ingress, %Sentinel.VisitorCounting.MediaMeter{
            camera_id: state.camera_id,
            channel: :primary
          })
          |> via_in(:input, auto_demand_size: 1)
          |> child(:parser, parser)
          |> via_in(:input, auto_demand_size: 1, toilet_capacity: 4)
          |> child(:decoder, decoder)
          |> via_in(:input, auto_demand_size: 1, toilet_capacity: 2)
          |> child(:sampler, Sentinel.VisitorCounting.SnapshotSampler)
          |> via_in(:input, auto_demand_size: 1, toilet_capacity: 2)
          |> child(:rgb, %Membrane.FFmpeg.SWScale.Converter{format: :RGB})
          |> via_in(:input, target_queue_size: 1, min_demand_factor: 1, toilet_capacity: 1)
          |> child(:jpeg, %Sentinel.VisitorCounting.SnapshotSink{
            source: state.source,
            generation: state.generation
          })

        {[spec: spec], state}
    end
  end

  def handle_child_notification({:snapshot_error, reason}, :sampler, _, state) do
    send(state.source, {:snapshot_error, self(), reason})
    {[terminate: :normal], state}
  end

  def handle_child_notification(_, _, _, state), do: {[], state}
  @impl true
  def handle_element_end_of_stream(:jpeg, :input, _, state), do: {[terminate: :normal], state}
  def handle_element_end_of_stream(_, _, _, state), do: {[], state}
end
