defmodule Sentinel.Monitoring.FileStorage do
  @moduledoc "Atomic publication of complete HLS manifests and segments."
  @behaviour Membrane.HTTPAdaptiveStream.Storage
  @enforce_keys [:directory]
  defstruct [:directory]

  @impl true
  def init(config), do: config

  @impl true
  def store(_parent, name, contents, _metadata, _context, state) do
    path = Path.join(state.directory, name)
    temporary = path <> ".pending"

    result =
      with :ok <- File.write(temporary, contents, [:binary]), do: File.rename(temporary, path)

    {result, state}
  end

  @impl true
  def remove(_parent, name, _context, state) do
    result =
      case File.rm(Path.join(state.directory, name)) do
        {:error, :enoent} -> :ok
        result -> result
      end

    {result, state}
  end
end
