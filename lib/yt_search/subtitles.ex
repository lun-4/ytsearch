defmodule YtSearch.Subtitle do
  use Ecto.Schema
  import Ecto.Query
  alias YtSearch.Data.SubtitleRepo

  @type t :: %__MODULE__{}

  # 12 hours ttl
  def ttl_seconds, do: 12 * 60 * 60

  @primary_key false

  schema "subtitles" do
    field(:youtube_id, :string, primary_key: true, autogenerate: false)
    field(:language, :string, primary_key: true)
    # NOTE: i chose a map here for ease of use, but it is possible (although unlikely)
    # that map serialization-deserialization may cause issues later on in terms
    # of CPU usage. if those happen, then i shall find a better way to store CTAs.
    # until then, it'd be premature optimization
    field(:cta, :map)
    timestamps()
  end

  @spec fetch(String.t()) :: [t()]
  def fetch(youtube_id) do
    query = from(s in __MODULE__, where: s.youtube_id == ^youtube_id, select: s)
    SubtitleRepo.replica().all(query)
  end

  def blob(nil), do: nil

  def blob(%__MODULE__{} = subtitle) do
    blob(subtitle_id(subtitle))
  end

  def blob(id) when is_bitstring(id) do
    case File.read(path_for(id)) do
      {:ok, data} -> data
      {:error, :enoent} -> nil
    end
  end

  def path_for(id) do
    "subtitles/#{id}"
  end

  def subtitle_id(%__MODULE__{youtube_id: youtube_id, language: language}) do
    "#{youtube_id}_#{language}"
  end

  def subtitle_data(%__MODULE__{} = subtitle) do
    blob(subtitle)
  end

  @spec insert(String.t(), String.t(), String.t() | nil, map()) :: t()
  def insert(youtube_id, language, subtitle_data, cta) do
    subtitle = %__MODULE__{
      youtube_id: youtube_id,
      language: language,
      cta: cta
    }
    |> SubtitleRepo.insert!(
      on_conflict: [
        set: [
          cta: cta
        ]
      ]
    )

    if subtitle_data do
      File.mkdir_p!("subtitles")
      File.write!(path_for(subtitle_id(subtitle)), subtitle_data)
    end

    subtitle
  end

  def find_like_and_subscribe(%__MODULE__{} = subtitle) do
    find_like_and_subscribe(subtitle_data(subtitle))
  end

  def find_like_and_subscribe(vtt_content) when is_binary(vtt_content) do
    YtSearch.Subtitle.CTAExtractor.detect_and_merge_engagement_prompts(vtt_content)
  end

  def parse_timestamp(timestamp) do
    [hours, minutes, seconds] = String.split(timestamp, ":")

    String.to_integer(hours) * 3600 +
      String.to_integer(minutes) * 60 +
      String.to_float(seconds)
  end

  defmodule Cleaner do
    require Logger

    alias YtSearch.Data.SubtitleRepo
    alias YtSearch.Data.SubtitleRepo.JanitorReplica
    alias YtSearch.Subtitle

    import Ecto.Query

    def tick() do
      Logger.info("cleaning subtitles...")

      expiry_time =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-Subtitle.ttl_seconds())
        |> DateTime.from_naive!("Etc/UTC")
        |> DateTime.to_unix()

      deleted_count =
        from(s in Subtitle,
          where:
            fragment("unixepoch(?)", s.inserted_at) <
              ^expiry_time,
          limit: 1000
        )
        |> JanitorReplica.all()
        |> Enum.map(fn subtitle ->
          # TODO: fix subtitle table
          # this hack is done because somehow id is nil,
          # likely due to bad table schema.
          subtitle
          |> Map.put(
            :id,
            case Map.get(subtitle, :id) do
              nil -> 0
              v -> v
            end
          )
        end)
        |> Enum.chunk_every(10)
        |> Enum.map(fn chunk ->
          chunk
          |> Enum.map(fn subtitle ->
            SubtitleRepo.delete(subtitle)
            File.rm(Subtitle.path_for(Subtitle.subtitle_id(subtitle)))
            1
          end)
          |> then(fn count ->
            :timer.sleep(1500)
            count
          end)
          |> Enum.sum()
        end)
        |> Enum.sum()

      Logger.info("deleted #{deleted_count} subtitles")
    end
  end
end
