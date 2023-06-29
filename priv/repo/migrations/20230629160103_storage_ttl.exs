defmodule YtSearch.Repo.Migrations.StorageTtl do
  use Ecto.Migration

  def up do
    alter table("links") do
      timestamps()
    end

    execute(fn ->
      repo().update_all("links", set: [inserted_at: DateTime.utc_now()])
      repo().update_all("links", set: [updated_at: DateTime.utc_now()])
    end)

    alter table("slots") do
      timestamps()
    end

    execute(fn ->
      repo().update_all("slots", set: [inserted_at: DateTime.utc_now()])
      repo().update_all("slots", set: [updated_at: DateTime.utc_now()])
    end)
  end

  def down do
    alter table("links") do
      remove :inserted_at
      remove :updated_at
    end

    alter table("slots") do
      remove :inserted_at
      remove :updated_at
    end
  end
end
