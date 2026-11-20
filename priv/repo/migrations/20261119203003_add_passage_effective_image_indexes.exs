defmodule Sentinel.Repo.Migrations.AddPassageEffectiveImageIndexes do
  use Ecto.Migration
  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:passage_events, ["(COALESCE(snapshot_received_at, crossed_at))", :id],
             name: :passage_effective_image_at,
             concurrently: true
           )

    create index(
             :passage_events,
             [:camera_id, "(COALESCE(snapshot_received_at, crossed_at))", :id],
             name: :passage_camera_effective_image_at,
             concurrently: true
           )
  end
end
