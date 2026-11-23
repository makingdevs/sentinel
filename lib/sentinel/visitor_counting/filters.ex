defmodule Sentinel.VisitorCounting.Filters do
  @moduledoc "Validated Mexico City calendar-day history filters. End date is inclusive in the form."
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key false
  embedded_schema do
    field :camera_id, :string, default: ""
    field :direction, :string, default: ""
    field :mode, :string, default: "range"
    field :day, :date
    field :from, :date
    field :until, :date
  end

  def changeset(attrs) do
    today = Sentinel.LocalTime.today()

    %__MODULE__{from: today, until: today, day: today}
    |> cast(attrs, [:camera_id, :direction, :from, :until, :mode, :day], empty_values: [])
    |> validate_required([:from, :until, :day, :mode])
    |> validate_inclusion(:mode, ["daily", "range"])
    |> validate_inclusion(:direction, ["", "entry", "exit"])
    |> validate_change(:camera_id, fn :camera_id, id ->
      cond do
        id == "" or Enum.any?(Sentinel.Monitoring.list_cameras(), &(&1.id == id)) -> []
        true -> [camera_id: "es inválida"]
      end
    end)
    |> validate_range()
  end

  defp validate_range(changeset) do
    cond do
      changeset.valid? and
          Date.compare(get_field(changeset, :from), get_field(changeset, :until)) == :gt ->
        add_error(changeset, :until, "debe ser posterior al inicio")

      true ->
        changeset
    end
  end

  def query(filters) do
    %{
      "camera_id" => filters.camera_id,
      "direction" => filters.direction,
      "from" => Sentinel.LocalTime.midnight_utc(filters.from),
      "until" => Sentinel.LocalTime.midnight_utc(Date.add(filters.until, 1))
    }
  end
end
