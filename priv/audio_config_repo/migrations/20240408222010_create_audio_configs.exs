defmodule YtSearch.Repo.Migrations.CreateAudioConfigs do
  use Ecto.Migration

  def change do
    create table(:audio_configs, primary_key: false) do
      add :youtube_id, :string, primary_key: true, autogenerate: false
      add :audio_config_data, :string
      timestamps()
    end
  end
end
