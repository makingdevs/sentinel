defmodule Sentinel.Monitoring.Pipeline do
  @moduledoc "RTSP to video-only H.264/H.265 HLS, adapted from membrane_demo/rtsp_to_hls."
  use Membrane.Pipeline

  @callback start(map()) :: {:ok, pid(), pid()} | {:error, term()}
  @callback stop(pid()) :: term()

  def start(options), do: Membrane.Pipeline.start_link(__MODULE__, options)
  def stop(pid), do: Membrane.Pipeline.terminate(pid, force?: true, timeout: 2_000)

  @impl true
  def handle_init(_ctx, options) do
    spec =
      child(:source, %Membrane.RTSP.Source{
        transport: :tcp,
        allowed_media_types: [:video],
        stream_uri: options.source_url,
        on_connection_closed: :raise_error
      })

    {[spec: spec], options}
  end

  @impl true
  def handle_child_notification({:set_up_tracks, tracks}, :source, _ctx, state) do
    case Enum.find(
           tracks,
           &(&1.type == :video and String.upcase(&1.rtpmap.encoding) in ["H264", "H265"])
         ) do
      nil ->
        send(state.owner, {:pipeline_error, self(), :unsupported_codec})
        {[terminate: :normal], state}

      track ->
        spec =
          get_child(:source)
          |> via_out(Pad.ref(:output, track.control_path))
          |> annotate(track, state)
          |> via_in(:input,
            options: [
              encoding:
                if(
                  Map.get(state, :engine, "off") == "off" and
                    String.upcase(track.rtpmap.encoding) == "H265",
                  do: :H265,
                  else: :H264
                ),
              track_name: "video_#{state.generation}",
              segment_duration: Membrane.Time.seconds(4)
            ]
          )
          |> child(:hls, %Membrane.HTTPAdaptiveStream.SinkBin{
            manifest_module: Membrane.HTTPAdaptiveStream.HLS,
            mode: :live,
            target_window_duration: Membrane.Time.seconds(24),
            persist?: false,
            storage: %Sentinel.Monitoring.FileStorage{directory: state.directory}
          })

        {[spec: spec], state}
    end
  end

  @impl true
  def handle_child_notification({:track_playable, _track}, :hls, _ctx, state) do
    send(state.owner, {:pipeline_ready, self()})
    {[], state}
  end

  def handle_child_notification(:end_of_stream, :hls, _ctx, state) do
    {[terminate: :normal], state}
  end

  def handle_child_notification({:detection_status, status}, :detector, _ctx, state) do
    send(state.owner, {:detection_status, self(), status})
    {[], state}
  end

  def handle_child_notification(_notification, _child, _ctx, state), do: {[], state}

  @impl true
  def handle_info(:retry_detector, _ctx, state) do
    if Map.get(state, :engine, "off") == "off",
      do: {[], state},
      else: {[notify_child: {:detector, :retry_detector}], state}
  end

  @doc false
  def annotate(builder, track, state) do
    if Map.get(state, :engine, "off") == "off" do
      builder
    else
      builder =
        case String.upcase(track.rtpmap.encoding) do
          "H264" ->
            builder
            |> child(:input_parser, %Membrane.H264.Parser{
              output_stream_structure: :annexb,
              output_alignment: :au
            })
            |> child(:decoder, Membrane.H264.FFmpeg.Decoder)

          "H265" ->
            builder
            |> child(:input_parser, %Membrane.H265.Parser{
              output_stream_structure: :annexb,
              output_alignment: :au
            })
            |> child(:decoder, Membrane.H265.FFmpeg.Decoder)
        end

      builder
      |> via_in(:input, auto_demand_size: 1)
      |> child(:to_rgb, %Membrane.FFmpeg.SWScale.Converter{format: :RGB, output_width: 640})
      |> via_in(:input, auto_demand_size: 1)
      |> child(:latest, %Sentinel.Detection.LatestFrame{
        engine: state.engine,
        generation: state.generation
      })
      |> via_in(:input, auto_demand_size: 1)
      |> child(:detector, %Sentinel.Detection.Filter{
        engine: state.engine,
        generation: state.generation
      })
      |> via_in(:input, auto_demand_size: 1)
      |> child(:drawer, Sentinel.Detection.Drawer)
      |> via_in(:input, auto_demand_size: 1)
      |> child(:to_i420, %Membrane.FFmpeg.SWScale.Converter{format: :I420})
      |> via_in(:input, auto_demand_size: 1)
      |> child(:encoder, %Membrane.H264.FFmpeg.Encoder{
        preset: :ultrafast,
        tune: :zerolatency,
        max_b_frames: 0,
        gop_size: 50
      })
    end
  end
end
