defmodule YtSearch.Mp4Link do
  use Ecto.Schema
  import Ecto.Query
  alias YtSearch.Data.LinkRepo
  alias YtSearch.TTL
  alias YtSearch.Slot
  require Logger

  @type t :: %__MODULE__{}

  @primary_key {:youtube_id, :string, autogenerate: false}

  # 30 minutes ttl for mp4 link
  def ttl_seconds, do: 30 * 60

  schema "links" do
    field(:mp4_link, :string)
    field(:youtube_metadata, :string)
    field(:error_reason, :string)
    timestamps()
  end

  @spec fetch_by_id(String.t()) :: Mp4Link.t() | nil
  def fetch_by_id(youtube_id) do
    query = from s in __MODULE__, where: s.youtube_id == ^youtube_id, select: s

    case LinkRepo.replica(youtube_id).one(query) do
      nil ->
        nil

      link ->
        if TTL.expired?(link, ttl_seconds()) do
          # do not expire in this case to prevent race conditions
          # the one that should remove it is the link janitor
          nil
        else
          link
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
      if expires_at != nil do
        # if youtube gives expiry timestamp, use it so that
        # (inserted_at + @ttl) = expiry
        # guaranteeding we expire it at the same time youtube expires it
        # if inserted_at + ttl should equal expiry
        # then inserted_at = expiry - ttl
        value
        |> Map.put(
          :inserted_at,
          DateTime.from_unix!(expires_at)
          |> DateTime.to_naive()
          |> NaiveDateTime.add(-ttl_seconds(), :second)
        )
      else
        value
      end
    end)
    |> then(fn link ->
      LinkRepo.insert!(
        link,
        on_conflict: [
          set:
            [
              youtube_metadata: link.youtube_metadata,
              mp4_link: link.mp4_link
            ] ++
              if link.inserted_at == nil do
                []
              else
                [inserted_at: link.inserted_at]
              end
        ]
      )
    end)
  end

  @error_atom_from_string %{
    "E01" => :video_unavailable,
    "E02" => :no_valid_formats_found,
    "E03" => :internal_error
  }

  @error_string_from_atom @error_atom_from_string
                          |> Enum.map(fn {k, v} -> {v, k} end)
                          |> Enum.into(%{})

  def error_atom_from_string(str) do
    @error_atom_from_string[str]
  end

  def error_string_from_atom(atom) do
    @error_string_from_atom[atom]
  end

  @spec insert_error(String.t(), atom()) :: Mp4Link.t()
  def insert_error(youtube_id, reason) do
    Logger.warning("link for yt id #{youtube_id} failed for #{inspect(reason)}")
    reason_string = error_string_from_atom(reason) || error_string_from_atom(:internal_error)

    %__MODULE__{
      youtube_id: youtube_id,
      youtube_metadata: nil,
      mp4_link: nil,
      error_reason: reason_string
    }
    |> LinkRepo.insert!(
      on_conflict: [
        set: [
          youtube_metadata: nil,
          mp4_link: nil,
          error_reason: reason_string
        ]
      ]
    )
  end

  @spec maybe_fetch_upstream(Slot.t()) ::
          {:ok, __MODULE__.t()} | {:error, __MODULE__.t()} | {:error, term()}
  def maybe_fetch_upstream(slot) do
    case fetch_by_id(slot.youtube_id) do
      nil ->
        fetch_mp4_link(slot)

      value ->
        {:ok, value}
    end
  end

  def meta(link) do
    case link.youtube_metadata do
      nil -> %{"age_limit" => 0}
      v -> v |> Jason.decode!()
    end
  end

  defp fetch_mp4_link(slot) do
    YtSearch.MetadataExtractor.Worker.mp4_link(slot.youtube_id)
  end

  defmodule Janitor do
    require Logger

    alias YtSearch.SlotUtilities
    alias YtSearch.Data.LinkRepo
    alias YtSearch.Mp4Link

    import Ecto.Query

    def tick() do
      Logger.info("cleaning links...")

      expiry_time =
        SlotUtilities.generate_unix_timestamp_integer() - Mp4Link.ttl_seconds()

      deleted_count =
        from(s in Mp4Link,
          where:
            fragment("unixepoch(?)", s.inserted_at) <
              ^expiry_time,
          limit: 3000
        )
        |> LinkRepo.JanitorReplica.all()
        |> Enum.chunk_every(10)
        |> Enum.map(fn chunk ->
          chunk
          |> Enum.map(fn link ->
            LinkRepo.delete(link)
            1
          end)
          |> then(fn count ->
            :timer.sleep(1500)
            count
          end)
          |> Enum.sum()
        end)
        |> Enum.sum()

      Logger.info("deleted #{deleted_count} links")
    end
  end
end
