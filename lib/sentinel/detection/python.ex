defmodule Sentinel.Detection.Python do
  @moduledoc "Bounded packet-4 IPC to a persistent Python process, without a shell."
  @behaviour Sentinel.Detection.Adapter
  alias Sentinel.Detection
  @max_packet 8 * 1024 * 1024

  @impl true
  def load do
    port =
      Port.open({:spawn_executable, Detection.python()}, [
        :binary,
        :exit_status,
        {:packet, 4},
        args: [
          Detection.get(:worker_script, Path.expand("python/worker.py")),
          Detection.model("pt")
        ],
        env: [{~c"YOLO_CONFIG_DIR", String.to_charlist(Path.expand("tmp/ultralytics"))}]
      ])

    case receive_json(port, 120_000) do
      {:ok, %{"ready" => true}} ->
        {:ok, port}

      _ ->
        close(port)
        {:error, :python_load_failed}
    end
  end

  @impl true
  def infer(port, frame) do
    header = Jason.encode!(Map.take(frame, [:width, :height, :frame_id]))
    payload = <<byte_size(header)::32, header::binary, frame.payload::binary>>

    cond do
      byte_size(payload) <= @max_packet ->
        Port.command(port, payload)

        case receive_json(port, Detection.get(:timeout_ms, 10000)) do
          {:ok, %{"frame_id" => id, "objects" => objects}}
          when id == frame.frame_id and is_list(objects) ->
            {:ok, objects}

          _ ->
            {:error, :python_inference_failed}
        end

      true ->
        {:error, :oversize_frame}
    end
  end

  @impl true
  def close(port) do
    case Port.info(port) do
      nil -> nil
      _info -> Port.close(port)
    end

    :ok
  end

  defp receive_json(port, timeout) do
    receive do
      {^port, {:data, data}} when byte_size(data) <= @max_packet -> Jason.decode(data)
      {^port, {:exit_status, _}} -> {:error, :python_exited}
    after
      timeout -> {:error, :python_timeout}
    end
  end
end
