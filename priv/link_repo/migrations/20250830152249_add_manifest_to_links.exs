defmodule YtSearch.Data.LinkRepo.Migrations.AddManifestToLinks do
  use Ecto.Migration

  def change do
    alter table(:links) do
      add :manifest_content, :text
    end
  end
end
