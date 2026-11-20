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
    field :snapshot_quality, :string
    field :snapshot_received_at, :utc_datetime_usec
    field :snapshot_width, :integer
    field :snapshot_height, :integer
    field :snapshot_fallback_reason, :string
    field :tracking_width, :integer
    field :tracking_height, :integer
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
    |> validate_inclusion(:snapshot_quality, ~w(primary secondary))
    |> validate_inclusion(:snapshot_fallback_reason, fallback_reasons())
    |> validate_number(:snapshot_width, greater_than: 0, less_than_or_equal_to: 3840)
    |> validate_number(:snapshot_height, greater_than: 0, less_than_or_equal_to: 2160)
    |> validate_number(:tracking_width, greater_than: 0)
    |> validate_number(:tracking_height, greater_than: 0)
    |> validate_provenance()
    |> check_constraint(:snapshot_quality, name: :passage_snapshot_provenance)
    |> unique_constraint(:dedupe_key)
  end

  def fallback_reasons,
    do: ~w(missing unavailable stale over_budget oversized generation_mismatch future)

  defp validate_provenance(changeset) do
    quality = get_field(changeset, :snapshot_quality)
    reason = get_field(changeset, :snapshot_fallback_reason)

    changeset =
      if quality do
        validate_required(changeset, [:snapshot_received_at, :snapshot_width, :snapshot_height])
      else
        changeset
      end

    cond do
      quality == "primary" and reason != nil ->
        add_error(changeset, :snapshot_fallback_reason, "must be absent for primary capture")

      quality == "secondary" and reason == nil ->
        add_error(changeset, :snapshot_fallback_reason, "is required for secondary fallback")

      quality == nil and
          Enum.any?(
            [:snapshot_received_at, :snapshot_width, :snapshot_height, :snapshot_fallback_reason],
            &(get_field(changeset, &1) != nil)
          ) ->
        add_error(changeset, :snapshot_quality, "is required with snapshot provenance")

      true ->
        changeset
    end
  end
end
