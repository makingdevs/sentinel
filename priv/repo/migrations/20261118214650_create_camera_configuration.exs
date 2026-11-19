defmodule Sentinel.Repo.Migrations.CreateCameraConfiguration do
  use Ecto.Migration

  def change do
    create table(:cameras, primary_key: false) do
      add :id, :string, primary_key: true
      add :branch, :string, null: false
      add :label, :string, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create table(:camera_sources) do
      add :camera_id, references(:cameras, type: :string, on_delete: :delete_all), null: false
      add :quality, :string, null: false
      add :url, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:camera_sources, [:camera_id, :quality])

    create constraint(:camera_sources, :camera_sources_quality_check,
             check: "quality IN ('principal', 'secundaria')"
           )

    create constraint(:camera_sources, :camera_sources_url_check, check: "btrim(url) <> ''")
  end
end
