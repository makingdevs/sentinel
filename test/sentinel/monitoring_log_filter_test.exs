defmodule Sentinel.MonitoringLogFilterTest do
  use ExUnit.Case, async: true

  test "redacts improper crash-report lists without removing the privacy filter" do
    event = %{msg: {:report, ["rtsp://user:secret@host/private" | :truncated]}}
    result = Sentinel.Monitoring.LogFilter.filter(event, [])
    refute inspect(result) =~ "secret"
    assert inspect(result) =~ "REDACTED"
  end

  test "redacts structs in native pipeline crash reports without disabling the logger filter" do
    event = %{
      msg: {:report, %{exception: %RuntimeError{message: "rtsp://user:secret@host/private"}}}
    }

    result = Sentinel.Monitoring.LogFilter.filter(event, [])
    refute inspect(result) =~ "secret"
    assert inspect(result) =~ "REDACTED"
  end

  test "redacts RTSP origins and credentials in strings and structured crash reports" do
    source = "rtsp://user:secret@10.0.0.1/private"

    assert %{msg: {:string, ["source=rtsp://[REDACTED]"]}} =
             Sentinel.Monitoring.LogFilter.filter(%{msg: {:string, ["source=#{source}"]}}, [])

    event = %{
      msg:
        {:report,
         %{
           state: %{source_url: source, password: "secret"},
           headers: [{"Authorization", "Basic abc"}]
         }}
    }

    result = Sentinel.Monitoring.LogFilter.filter(event, [])
    refute inspect(result) =~ "secret"
    refute inspect(result) =~ "10.0.0.1"
    refute inspect(result) =~ "Basic abc"
  end
end
