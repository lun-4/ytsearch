defmodule YtSearch.Mp4Link do
  use Ecto.Schema
  import Ecto.Query
  alias YtSearch.Repo
  alias YtSearch.Youtube
  alias YtSearch.TTL
  alias YtSearch.Slot

  @type t :: %__MODULE__{}

  @primary_key {:youtube_id, :string, autogenerate: false}

  # 30 minutes ttl for mp4 link
  def ttl_seconds, do: 30 * 60

  schema "links" do
    field(:mp4_link, :string)
    field(:youtube_metadata, :string)
    timestamps()
  end

  @spec fetch_by_id(String.t()) :: Mp4Link.t()
  def fetch_by_id(youtube_id) do
    query = from s in __MODULE__, where: s.youtube_id == ^youtube_id, select: s

    case Repo.one(query) do
      nil ->
        {:ok, nil}

      link ->
        if TTL.expired?(link, ttl_seconds()) do
          Repo.delete!(link)
          {:ok, nil}
        else
          if link.mp4_link == nil do
            {:error, :video_unavailable}
          else
            {:ok, link}
          end
        end
    end
  end

  @spec insert(String.t(), String.t(), Integer.t() | nil, String.t()) :: Mp4Link.t()
  def insert(youtube_id, mp4_link, expires_at, youtube_metadata) do
    %__MODULE__{
      youtube_id: youtube_id,
      youtube_metadata: youtube_metadata |> Jason.encode!(),
      mp4_link: mp4_link
    }
    |> then(fn value ->
      unless expires_at == nil do
        # if youtube gives expiry timestamp, use it so that
        # (inserted_at + @ttl) = expiry
        # guaranteeding we expire it at the same time youtube expires it
        value
        |> Ecto.Changeset.change(
          inserted_at: DateTime.from_unix!(expires_at) |> DateTime.to_naive()
        )
      else
        value
      end
    end)
    |> Repo.insert!()
  end

  def insert_video_not_found(youtube_id) do
    %__MODULE__{
      youtube_id: youtube_id,
      youtube_metadata: nil,
      mp4_link: nil
    }
    |> Repo.insert!()
  end

  @spec maybe_fetch_upstream(Slot.t()) :: {:ok, __MODULE__.t()}
  def maybe_fetch_upstream(slot) do
    case fetch_by_id(slot.youtube_id) do
      {:ok, nil} ->
        fetch_mp4_link(slot)

      value ->
        value
    end
  end

  def meta(link) do
    case link.youtube_metadata do
      nil -> %{"age_limit" => 0}
      v -> v |> Jason.decode!()
    end
  end

  defp fetch_mp4_link(slot) do
    Mutex.under(Mp4LinkMutex, slot.youtube_id, fn ->
      # refetch to prevent double fetch

      case fetch_by_id(slot.youtube_id) do
        {:ok, nil} ->
          # get mp4 from ytdlp
          case Youtube.fetch_mp4_link(slot.youtube_id) do
            {:ok, {link_string, expires_at_unix_timestamp, meta}} ->
              {:ok, insert(slot.youtube_id, link_string, expires_at_unix_timestamp, meta)}

            {:error, :video_unavailable} ->
              insert_video_not_found(slot.youtube_id)
              {:error, :video_unavailable}
          end

        value ->
          value
      end
    end)
  end

  defmodule Janitor do
    require Logger

    alias YtSearch.Repo
    alias YtSearch.Mp4Link

    import Ecto.Query

    def tick() do
      Logger.info("cleaning links...")

      expiry_time =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-Mp4Link.ttl_seconds())

      {deleted_count, _entities} =
        from(s in Mp4Link,
          where:
            s.inserted_at <
              ^expiry_time
        )
        |> Repo.delete_all()

      Logger.info("deleted #{deleted_count} links")
    end
  end
end
