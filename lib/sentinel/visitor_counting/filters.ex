defmodule Sentinel.VisitorCounting.Filters do
  @moduledoc "Validated UTC calendar-day history filters. End date is inclusive in the form."
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
    %__MODULE__{from: Date.utc_today(), until: Date.utc_today(), day: Date.utc_today()}
    |> cast(attrs, [:camera_id, :direction, :from, :until, :mode, :day], empty_values: [])
    |> validate_required([:from, :until, :day, :mode])
    |> validate_inclusion(:mode, ["daily", "range"])
    |> validate_inclusion(:direction, ["", "entry", "exit"])
    |> validate_change(:camera_id, fn :camera_id, id ->
      if id == "" or Enum.any?(Sentinel.Monitoring.list_cameras(), &(&1.id == id)),
        do: [],
        else: [camera_id: "es inválida"]
    end)
    |> validate_range()
  end

  defp validate_range(changeset) do
    if changeset.valid? and
         Date.compare(get_field(changeset, :from), get_field(changeset, :until)) == :gt,
       do: add_error(changeset, :until, "debe ser posterior al inicio"),
       else: changeset
  end

  def query(filters) do
    %{
      "camera_id" => filters.camera_id,
      "direction" => filters.direction,
      "from" => DateTime.new!(filters.from, ~T[00:00:00], "Etc/UTC"),
      "until" => DateTime.new!(Date.add(filters.until, 1), ~T[00:00:00], "Etc/UTC")
    }
  end
end
