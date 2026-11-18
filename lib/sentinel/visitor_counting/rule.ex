defmodule Sentinel.VisitorCounting.Rule do
  @moduledoc "A versioned directed counting line in normalized image coordinates."
  use Ecto.Schema
  import Ecto.Changeset

  schema "visitor_counting_rules" do
    field :camera_id, :string
    field :x1, :float, default: 0.1
    field :y1, :float, default: 0.5
    field :x2, :float, default: 0.9
    field :y2, :float, default: 0.5
    field :engine, :string, default: "python"
    field :entry_direction, :string, default: "positive"
    field :confidence, :float, default: 0.5
    field :hysteresis, :float, default: 0.025
    field :min_hits, :integer, default: 3
    field :max_missed, :integer, default: 5
    field :enabled, :boolean, default: false
    field :revision, :integer, default: 1
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(rule, attrs) do
    rule
    |> cast(attrs, [
      :x1,
      :y1,
      :x2,
      :y2,
      :engine,
      :entry_direction,
      :confidence,
      :hysteresis,
      :min_hits,
      :max_missed,
      :enabled
    ])
    |> validate_required([
      :camera_id,
      :x1,
      :y1,
      :x2,
      :y2,
      :engine,
      :entry_direction,
      :confidence,
      :hysteresis,
      :min_hits,
      :max_missed,
      :enabled
    ])
    |> validate_inclusion(:engine, ~w(python elixir))
    |> validate_inclusion(:entry_direction, ~w(positive negative))
    |> validate_number(:confidence, greater_than_or_equal_to: 0.35, less_than_or_equal_to: 1)
    |> validate_number(:hysteresis, greater_than: 0, less_than_or_equal_to: 0.2)
    |> validate_number(:min_hits, greater_than_or_equal_to: 2, less_than_or_equal_to: 30)
    |> validate_number(:max_missed, greater_than_or_equal_to: 0, less_than_or_equal_to: 30)
    |> coordinates()
    |> validate_camera()
    |> unique_constraint(:camera_id)
    |> optimistic_lock(:revision)
  end

  defp coordinates(changeset) do
    changeset =
      Enum.reduce([:x1, :y1, :x2, :y2], changeset, fn field, acc ->
        validate_number(acc, field, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
      end)

    with true <- changeset.valid?,
         x1 = get_field(changeset, :x1),
         y1 = get_field(changeset, :y1),
         x2 = get_field(changeset, :x2),
         y2 = get_field(changeset, :y2),
         true <- (x2 - x1) ** 2 + (y2 - y1) ** 2 < 0.0025 do
      add_error(changeset, :x2, "la línea debe medir al menos 5% de la imagen")
    else
      _ -> changeset
    end
  end

  defp validate_camera(changeset) do
    case Sentinel.Monitoring.fetch_camera(get_field(changeset, :camera_id)) do
      {:ok, _} -> changeset
      _ -> add_error(changeset, :camera_id, "cámara desconocida")
    end
  end
end
