defmodule Sentinel.Repo.Migrations.AddPassageSnapshotProvenance do
  use Ecto.Migration

  def change do
    alter table(:passage_events) do
      add :snapshot_quality, :string
      add :snapshot_received_at, :utc_datetime_usec
      add :snapshot_width, :integer
      add :snapshot_height, :integer
      add :snapshot_fallback_reason, :string
      add :tracking_width, :integer
      add :tracking_height, :integer
    end

    create constraint(:passage_events, :passage_snapshot_provenance,
             check: """
             (tracking_width IS NULL OR tracking_width > 0) AND
             (tracking_height IS NULL OR tracking_height > 0) AND
             (
               (snapshot_quality IS NULL AND snapshot_received_at IS NULL AND
                snapshot_width IS NULL AND snapshot_height IS NULL AND snapshot_fallback_reason IS NULL)
               OR
               (snapshot_quality IS NOT NULL AND snapshot_quality IN ('primary', 'secondary') AND
                snapshot_received_at IS NOT NULL AND
                snapshot_width IS NOT NULL AND snapshot_width BETWEEN 1 AND 3840 AND
                snapshot_height IS NOT NULL AND snapshot_height BETWEEN 1 AND 2160 AND
                ((snapshot_quality = 'primary' AND snapshot_fallback_reason IS NULL) OR
                 (snapshot_quality = 'secondary' AND snapshot_fallback_reason IS NOT NULL AND
                  snapshot_fallback_reason IN ('missing', 'unavailable', 'stale', 'over_budget',
                                              'oversized', 'generation_mismatch', 'future'))))
             )
             """
           )
  end
end
