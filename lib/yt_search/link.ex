defmodule YtSearch.Mp4Link do
  use Ecto.Schema
  import Ecto.Query
  alias YtSearch.Repo
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
    reason_string = error_string_from_atom(reason) || "internal_error"

    %__MODULE__{
      youtube_id: youtube_id,
      youtube_metadata: nil,
      mp4_link: nil,
      error_reason: reason_string
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
    YtSearch.MetadataExtractor.Worker.mp4_link(slot.youtube_id)
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
