defmodule YtSearch.Repo.Migrations.AddErrorReasonToMp4Link do
  use Ecto.Migration

  def change do
    alter table(:links) do
      add :error_reason, :string
    end
  end
end
