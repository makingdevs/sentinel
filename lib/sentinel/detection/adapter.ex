defmodule Sentinel.Detection.Adapter do
  @moduledoc "Persistent inference backend; receives RGB frames and returns pixel xyxy objects."
  @callback load() :: {:ok, term()} | {:error, term()}
  @callback infer(term(), map()) :: {:ok, list()} | {:error, term()}
  @callback close(term()) :: term()
end
