defmodule Sentinel.Detection.FixturePipeline do
  @moduledoc false
  use Membrane.Pipeline

  @impl true
  def handle_init(_ctx, opts) do
    codec = Map.get(opts, :codec, "H264")

    parser =
      if codec == "H264" do
        %Membrane.H264.Parser{
          output_stream_structure: :annexb,
          output_alignment: :au,
          generate_best_effort_timestamps: %{framerate: {25, 1}, add_dts_offset: false}
        }
      else
        %Membrane.H265.Parser{
          output_stream_structure: :annexb,
          output_alignment: :au,
          generate_best_effort_timestamps: %{framerate: {25, 1}, add_dts_offset: false}
        }
      end

    spec =
      child(:file, %Membrane.File.Source{location: opts.file})
      |> child(:parser, parser)
      |> child(:pace, Membrane.Realtimer)
      |> Sentinel.Monitoring.Pipeline.annotate(%{rtpmap: %{encoding: codec}}, opts)
      |> child(:measure, %Membrane.Debug.Filter{
        handle_buffer: fn buffer ->
          :telemetry.execute(
            [:sentinel, :benchmark, :output],
            %{
              pts: buffer.pts,
              lag_ms:
                System.monotonic_time(:millisecond) - opts.started_ms - buffer.pts / 1_000_000
            },
            %{generation: opts.generation}
          )
        end
      })
      |> via_in(:input,
        options: [
          encoding: if(opts.engine == "off" and codec == "H265", do: :H265, else: :H264),
          track_name: "video_#{opts.generation}",
          segment_duration: Membrane.Time.seconds(4)
        ]
      )
      |> child(:hls, %Membrane.HTTPAdaptiveStream.SinkBin{
        manifest_module: Membrane.HTTPAdaptiveStream.HLS,
        mode: :live,
        target_window_duration: Membrane.Time.seconds(24),
        persist?: false,
        storage: %Sentinel.Monitoring.FileStorage{directory: opts.directory}
      })

    {[spec: spec], opts}
  end

  @impl true
  def handle_child_notification({:detection_status, status}, :detector, _ctx, state) do
    send(state.owner, {:detection_status, self(), status})
    {[], state}
  end

  def handle_child_notification({:track_playable, _}, :hls, _ctx, state) do
    send(state.owner, {:pipeline_ready, self()})
    {[], state}
  end

  def handle_child_notification(_msg, _child, _ctx, state), do: {[], state}
end
