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
    require Logger

    alias YtSearch.Data.AudioConfigRepo
    alias YtSearch.Data.AudioConfigRepo.JanitorReplica
    alias YtSearch.AudioConfig

    import Ecto.Query

    def tick() do
      Logger.info("cleaning audio configs...")

      expiry_time =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-AudioConfig.ttl_seconds())
        |> DateTime.from_naive!("Etc/UTC")
        |> DateTime.to_unix()

      deleted_count =
        from(s in AudioConfig,
          where:
            fragment("unixepoch(?)", s.inserted_at) <
              ^expiry_time,
          limit: 1000
        )
        |> JanitorReplica.all()
        |> Enum.chunk_every(10)
        |> Enum.map(fn chunk ->
          chunk
          |> Enum.map(fn audio_config ->
            AudioConfigRepo.delete(audio_config)
            1
          end)
          |> then(fn count ->
            :timer.sleep(1500)
            count
          end)
          |> Enum.sum()
        end)
        |> Enum.sum()

      Logger.info("deleted #{deleted_count} audio configs")
    end
  end
end
