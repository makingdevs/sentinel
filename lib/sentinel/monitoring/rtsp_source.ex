defmodule Sentinel.Monitoring.RTSPSource do
  @moduledoc "Shared video-only RTSP source configuration and supported codec selection."
  import Membrane.ChildrenSpec

  def spec(url) do
    child(:source, %Membrane.RTSP.Source{
      transport: :tcp,
      allowed_media_types: [:video],
      stream_uri: url,
      on_connection_closed: :raise_error
    })
  end

  def video_track(tracks), do: Enum.find(tracks, &supported_video?/1)

  defp supported_video?(%{type: :video, rtpmap: %{encoding: encoding}}),
    do: String.upcase(encoding) in ~w(H264 H265)

  defp supported_video?(_track), do: false

  def decoder("H264"), do: Membrane.H264.FFmpeg.Decoder
  def decoder("H265"), do: Membrane.H265.FFmpeg.Decoder

  def parser("H264"),
    do: %Membrane.H264.Parser{output_stream_structure: :annexb, output_alignment: :au}

  def parser("H265"),
    do: %Membrane.H265.Parser{output_stream_structure: :annexb, output_alignment: :au}
end
