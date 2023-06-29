defmodule YtSearch.Mp4Link do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  import Ecto, only: [assoc: 2]
  alias YtSearch.Repo
  alias YtSearch.Youtube
  alias YtSearch.TTL

  @type t :: %__MODULE__{}

  @primary_key {:youtube_id, :string, autogenerate: false}

  # 30 minutes ttl for mp4 link
  @ttl 30 * 60

  schema "links" do
    field(:mp4_link, :string)
    timestamps()
  end

  @spec fetch_by_id(String.t()) :: Mp4Link.t()
  def fetch_by_id(youtube_id) do
    query = from s in __MODULE__, where: s.youtube_id == ^youtube_id, select: s

    case Repo.one(query) do
      nil ->
        nil

      link ->
        if TTL.expired?(link, @ttl) do
          Repo.delete!(link)
          nil
        else
          link
        end
    end
  end

  @spec insert(String.t(), String.t()) :: Mp4Link.t()
  def insert(youtube_id, mp4_link) do
    %__MODULE__{youtube_id: youtube_id, mp4_link: mp4_link}
    |> Repo.insert!()
  end

  @spec maybe_fetch_upstream(String.t(), String.t()) :: String.t()
  def maybe_fetch_upstream(youtube_id, youtube_url) do
    case fetch_by_id(youtube_id) do
      nil ->
        fetch_mp4_link(youtube_id, youtube_url)

      data ->
        data.mp4_link
    end
  end

  defp fetch_mp4_link(youtube_id, youtube_url) do
    Mutex.under(Mp4LinkMutex, youtube_id, fn ->
      # refetch to prevent double fetch
      case fetch_by_id(youtube_id) do
        nil ->
          # get mp4 from ytdlp
          new_mp4_link = Youtube.fetch_mp4_link(youtube_id)
          insert(youtube_id, new_mp4_link)
          new_mp4_link

        link ->
          link.mp4_link
      end
    end)
  end
end
