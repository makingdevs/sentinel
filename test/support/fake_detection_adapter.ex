defmodule Sentinel.TestDetectionAdapter do
  @behaviour Sentinel.Detection.Adapter
  def load, do: {:ok, :fake_model}
  def infer(:fake_model, %{payload: "failure"}), do: {:error, :fixture_failure}

  def infer(:fake_model, _frame),
    do: {:ok, [%{"class_id" => 0, "confidence" => 0.9, "xyxy" => [0, 0, 1, 1]}]}

  def close(:fake_model), do: :ok
end
