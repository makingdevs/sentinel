defmodule Sentinel.Monitoring.LogFilter do
  @moduledoc false

  def filter(%{msg: message} = event, _config), do: %{event | msg: redact(message)}

  defp redact(value) when is_binary(value) do
    String.replace(value, ~r{rtsp://[^\s"<>]+}, "rtsp://[REDACTED]")
  end

  defp redact(value) when is_list(value) do
    if List.ascii_printable?(value) do
      value |> List.to_string() |> redact() |> String.to_charlist()
    else
      Enum.map(value, &redact/1)
    end
  end

  defp redact({key, _value})
       when key in [:password, :userinfo, "password", "Authorization", "authorization"] do
    {key, "[REDACTED]"}
  end

  defp redact(value) when is_tuple(value),
    do: value |> Tuple.to_list() |> Enum.map(&redact/1) |> List.to_tuple()

  defp redact(value) when is_map(value), do: value |> Map.to_list() |> Map.new(&redact/1)
  defp redact(value), do: value
end
