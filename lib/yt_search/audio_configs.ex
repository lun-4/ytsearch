defmodule YtSearch.AudioConfig do
  use Ecto.Schema
  import Ecto.Query
  alias YtSearch.Data.AudioConfigRepo

  @type t :: %__MODULE__{}

  # 12 hours ttl
  def ttl_seconds, do: 12 * 60 * 60

  @primary_key false

  schema "audio_configs" do
    field(:youtube_id, :string, primary_key: true, autogenerate: false)
    field(:audio_config_data, :string)
    timestamps()
  end

  @spec fetch(String.t()) :: AudioConfig.t() | nil
  def fetch(youtube_id) do
    query = from s in __MODULE__, where: s.youtube_id == ^youtube_id, select: s
    AudioConfigRepo.replica().one(query)
  end

  @spec insert(String.t(), String.t()) :: AudioConfig.t()
  def insert(youtube_id, audio_config_data)
      when is_bitstring(youtube_id) and is_bitstring(audio_config_data) do
    %__MODULE__{youtube_id: youtube_id, audio_config_data: audio_config_data}
    |> AudioConfigRepo.insert!(
      on_conflict: [
        set: [
          audio_config_data: audio_config_data
        ]
      ]
    )
  end

  defmodule Cleaner do
    alias YtSearch.Data.AudioConfigRepo
    alias YtSearch.AudioConfig

    def tick() do
      YtSearch.Janitor.sweep(
        name: "audio configs",
        schema: AudioConfig,
        repo: AudioConfigRepo,
        replica: AudioConfigRepo.JanitorReplica,
        keys: [:youtube_id],
        expiry_column: :inserted_at,
        ttl: AudioConfig.ttl_seconds(),
        select_limit: 1000,
        chunk_size: 500,
        sleep_ms: 250
      )
    end
  end
end
