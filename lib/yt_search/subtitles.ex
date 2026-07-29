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

  def path_for(%__MODULE__{} = subtitle) do
    path_for(subtitle_id(subtitle))
  end

  # the janitor hands us a plain map of the key columns, not a full struct
  def path_for(%{youtube_id: youtube_id, language: language}) do
    path_for("#{youtube_id}_#{language}")
  end

  def path_for(id) when is_binary(id) do
    "subtitles/#{id}"
  end

  def subtitle_id(%__MODULE__{youtube_id: youtube_id, language: language}) do
    "#{youtube_id}_#{language}"
  end

  @spec insert(String.t(), String.t(), String.t() | nil, map()) :: t()
  def insert(youtube_id, language, subtitle_data, cta) do
    subtitle =
      %__MODULE__{
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
      File.write!(path_for(subtitle), subtitle_data)
    end

    subtitle
  end

  def find_like_and_subscribe(%__MODULE__{} = subtitle) do
    find_like_and_subscribe(blob(subtitle))
  end

  def find_like_and_subscribe(vtt_content) when is_binary(vtt_content) do
    YtSearch.Subtitle.CTAExtractorHTTP.detect_and_merge_engagement_prompts(vtt_content)
  end

  def parse_timestamp(timestamp) do
    [hours, minutes, seconds] = String.split(timestamp, ":")

    String.to_integer(hours) * 3600 +
      String.to_integer(minutes) * 60 +
      String.to_float(seconds)
  end

  defmodule Cleaner do
    alias YtSearch.Data.SubtitleRepo
    alias YtSearch.Subtitle

    def tick() do
      YtSearch.Janitor.sweep(
        name: "subtitles",
        schema: Subtitle,
        repo: SubtitleRepo,
        replica: SubtitleRepo.JanitorReplica,
        keys: [:youtube_id, :language],
        expiry_column: :inserted_at,
        ttl: Subtitle.ttl_seconds(),
        select_limit: 1000,
        chunk_size: 200,
        sleep_ms: 250,
        file_path: &Subtitle.path_for/1
      )
    end
  end
end
