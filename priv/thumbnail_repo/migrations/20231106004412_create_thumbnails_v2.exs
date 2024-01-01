defmodule YtSearch.Repo.Migrations.CreateThumbnailsV2 do
  use Ecto.Migration

  def change do
    # copied from CreateSlotsV3 migration

    default_expires_now =
      NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_iso8601()

    create table(:thumbnails_v2, primary_key: false) do
      add :id, :string, primary_key: true, autogenerate: false
      add :mime_type, :string
      timestamps()

      add :expires_at, :naive_datetime, default: default_expires_now
      add :used_at, :naive_datetime, default: default_expires_now
      add :keepalive, :boolean, default: false
    end

    create index(:thumbnails_v2, ["unixepoch(expires_at)"])
    create index(:thumbnails_v2, ["unixepoch(used_at)"])
  end
end
