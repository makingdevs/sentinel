defmodule Sentinel.Repo.Migrations.CreateVisitorCountingTables do
  use Ecto.Migration

  def change do
    create table(:visitor_counting_rules) do
      add :camera_id, :string, null: false
      for field <- [:x1, :y1, :x2, :y2], do: add(field, :float, null: false)
      add :engine, :string, null: false
      add :entry_direction, :string, null: false
      add :confidence, :float, null: false
      add :hysteresis, :float, null: false
      add :min_hits, :integer, null: false
      add :max_missed, :integer, null: false
      add :enabled, :boolean, null: false, default: false
      add :revision, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:visitor_counting_rules, :normalized_line,
             check:
               "x1 BETWEEN 0 AND 1 AND y1 BETWEEN 0 AND 1 AND x2 BETWEEN 0 AND 1 AND y2 BETWEEN 0 AND 1 AND ((x2-x1)*(x2-x1)+(y2-y1)*(y2-y1)) >= 0.0025"
           )

    create constraint(:visitor_counting_rules, :valid_settings,
             check:
               "engine IN ('python','elixir') AND entry_direction IN ('positive','negative') AND confidence BETWEEN 0.35 AND 1 AND hysteresis > 0 AND hysteresis <= 0.2 AND min_hits BETWEEN 2 AND 30 AND max_missed BETWEEN 0 AND 30 AND revision > 0"
           )

    create table(:passage_events) do
      add :camera_id, :string, null: false
      add :rule_revision, :integer, null: false
      add :crossed_at, :utc_datetime_usec, null: false
      add :direction, :string, null: false
      add :tracking_session_id, :string, null: false
      add :track_id, :bigint, null: false
      add :crossing_number, :integer, null: false
      add :confidence, :float, null: false
      add :bbox, :map, null: false
      add :snapshot_key, :string, null: false
      add :dedupe_key, :string, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create constraint(:passage_events, :valid_passage,
             check:
               "direction IN ('entry','exit') AND confidence BETWEEN 0 AND 1 AND track_id > 0 AND crossing_number > 0 AND rule_revision > 0"
           )

    # DB uniqueness is the final protection against concurrent writers.
    create unique_index(:visitor_counting_rules, [:camera_id])
    create unique_index(:passage_events, [:dedupe_key])
    create index(:passage_events, [:camera_id, "crossed_at DESC", "id DESC"])
    create index(:passage_events, ["crossed_at DESC", "id DESC"])
  end
end
