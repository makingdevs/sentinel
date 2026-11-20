defmodule Sentinel.Monitoring.Camera do
  @moduledoc "Descriptive camera metadata; connection details live in CameraSource."
  use Ecto.Schema
  import Ecto.Changeset

  @colors ~w(slate blue cyan teal green lime amber orange rose pink purple indigo)
  @color_values %{
    "slate" => "#94a3b8",
    "blue" => "#60a5fa",
    "cyan" => "#22d3ee",
    "teal" => "#2dd4bf",
    "green" => "#4ade80",
    "lime" => "#a3e635",
    "amber" => "#fbbf24",
    "orange" => "#fb923c",
    "rose" => "#fb7185",
    "pink" => "#f472b6",
    "purple" => "#c084fc",
    "indigo" => "#818cf8"
  }
  def colors, do: @colors
  def color_value(color), do: Map.get(@color_values, color, @color_values["slate"])

  @primary_key {:id, :string, autogenerate: false}
  schema "cameras" do
    field :branch, :string
    field :label, :string
    field :color, :string, default: "slate"
    field :archived_at, :utc_datetime_usec
    has_many :sources, Sentinel.Monitoring.CameraSource
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(camera, attrs) do
    camera
    |> cast(attrs, [:id, :branch, :label, :color, :archived_at])
    |> validate_required([:id, :branch, :label])
    |> validate_format(:id, ~r/\A[a-zA-Z0-9_-]+\z/)
    |> validate_inclusion(:color, @colors)
    |> unique_constraint(:id, name: :cameras_pkey)
  end
end
