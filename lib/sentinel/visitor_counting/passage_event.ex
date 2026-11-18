defmodule Sentinel.VisitorCounting.PassageEvent do
  @moduledoc "Metadata for one crossing, never a persistent person identity."
  use Ecto.Schema
  import Ecto.Changeset

  schema "passage_events" do
    field :camera_id, :string
    field :rule_revision, :integer
    field :crossed_at, :utc_datetime_usec
    field :direction, :string
    field :tracking_session_id, :string
    field :track_id, :integer
    field :crossing_number, :integer
    field :confidence, :float
    field :bbox, :map
    field :snapshot_key, :string
    field :dedupe_key, :string
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(attrs) do
    %__MODULE__{}
    |> change(attrs)
    |> validate_required([
      :camera_id,
      :rule_revision,
      :crossed_at,
      :direction,
      :tracking_session_id,
      :track_id,
      :crossing_number,
      :confidence,
      :bbox,
      :snapshot_key,
      :dedupe_key
    ])
    |> validate_inclusion(:direction, ~w(entry exit))
    |> validate_number(:confidence, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> validate_number(:track_id, greater_than: 0)
    |> validate_number(:crossing_number, greater_than: 0)
    |> unique_constraint(:dedupe_key)
  end
end
