defmodule Sentinel.Repo.Migrations.AddCameraCatalogColorAndArchive do
  use Ecto.Migration

  def change do
    alter table(:cameras) do
      add :color, :string, null: false, default: "slate"
      add :archived_at, :utc_datetime_usec
    end

    execute(
      """
      UPDATE cameras SET color = (ARRAY['slate','blue','cyan','teal','green','lime','amber','orange','rose','pink','purple','indigo'])[
        mod(abs(hashtext(id)::bigint), 12)::integer + 1
      ]
      """,
      "SELECT 1"
    )

    create constraint(:cameras, :cameras_color_check,
             check:
               "color IN ('slate', 'blue', 'cyan', 'teal', 'green', 'lime', 'amber', 'orange', 'rose', 'pink', 'purple', 'indigo')"
           )
  end
end
