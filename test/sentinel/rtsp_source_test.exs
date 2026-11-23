defmodule Sentinel.Monitoring.RTSPSourceTest do
  use ExUnit.Case, async: true
  alias Sentinel.Monitoring.RTSPSource

  test "selects the first supported video track without changing codec preference" do
    h265 = %{type: :video, rtpmap: %{encoding: "h265"}, control_path: "primary"}
    h264 = %{type: :video, rtpmap: %{encoding: "H264"}, control_path: "secondary"}
    audio = %{type: :audio, rtpmap: %{encoding: "H264"}}
    unsupported = %{type: :video, rtpmap: %{encoding: "VP9"}}
    assert RTSPSource.video_track([audio, unsupported, h265, h264]) == h265
    assert RTSPSource.video_track([audio, unsupported]) == nil
    assert RTSPSource.video_track([]) == nil
  end

  test "both codecs retain access-unit Annex B parsing and the matching decoder" do
    assert %Membrane.H264.Parser{output_stream_structure: :annexb, output_alignment: :au} =
             RTSPSource.parser("H264")

    assert %Membrane.H265.Parser{output_stream_structure: :annexb, output_alignment: :au} =
             RTSPSource.parser("H265")

    assert RTSPSource.decoder("H264") == Membrane.H264.FFmpeg.Decoder
    assert RTSPSource.decoder("H265") == Membrane.H265.FFmpeg.Decoder
  end

  test "pipelines preserve unsupported-codec notifications and normal termination" do
    state = %{owner: self()}
    tracks = [%{type: :video, rtpmap: %{encoding: "VP9"}}]

    assert {[terminate: :normal], ^state} =
             Sentinel.Monitoring.Pipeline.handle_child_notification(
               {:set_up_tracks, tracks},
               :source,
               %{},
               state
             )

    assert_receive {:pipeline_error, _, :unsupported_codec}

    assert {[terminate: :normal], ^state} =
             Sentinel.VisitorCounting.Pipeline.handle_child_notification(
               {:set_up_tracks, tracks},
               :source,
               %{},
               state
             )

    assert_receive {:analytics_error, _, :unsupported_codec}

    assert {[terminate: :normal], ^state} =
             Sentinel.VisitorCounting.SnapshotPipeline.handle_child_notification(
               {:set_up_tracks, tracks},
               :source,
               %{},
               state
             )
  end
end
