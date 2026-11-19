defmodule Sentinel.Monitoring.Camera do
  @moduledoc "Descriptive camera metadata; connection details live in CameraSource."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  schema "cameras" do
    field :branch, :string
    field :label, :string
    has_many :sources, Sentinel.Monitoring.CameraSource
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(camera, attrs) do
    camera
    |> cast(attrs, [:id, :branch, :label])
    |> validate_required([:id, :branch, :label])
    |> validate_format(:id, ~r/\A[a-zA-Z0-9_-]+\z/)
    |> unique_constraint(:id, name: :cameras_pkey)
  end
end
