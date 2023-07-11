defmodule YtSearch.Subtitle do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  import Ecto, only: [assoc: 2]
  alias YtSearch.Repo
  alias YtSearch.Youtube
  alias YtSearch.TTL

  @type t :: %__MODULE__{}

  # 12 hours ttl
  def ttl_seconds, do: 12 * 60 * 60

  # @primary_key {:youtube_id, :string, autogenerate: false}

  schema "subtitles" do
    field(:youtube_id, :string, primary_key: true, autogenerate: false)
    field(:language, :string, primary_key: true)
    field(:subtitle_data, :string)
    timestamps()
  end

  @spec fetch(String.t()) :: [Subtitle.t()]
  def fetch(youtube_id) do
    query = from s in __MODULE__, where: s.youtube_id == ^youtube_id, select: s
    Repo.all(query)
  end

  @spec insert(String.t(), String.t(), String.t() | nil) :: Subtitle.t()
  def insert(youtube_id, language, subtitle_data) do
    %__MODULE__{youtube_id: youtube_id, language: language, subtitle_data: subtitle_data}
    |> Repo.insert!()
  end

  defmodule Cleaner do
    use GenServer
    require Logger

    alias YtSearch.Repo
    alias YtSearch.Subtitle

    import Ecto.Query

    def start_link(arg) do
      GenServer.start_link(__MODULE__, arg)
    end

    @impl true
    def init(_arg) do
      schedule_work()
      {:ok, %{}}
    end

    def handle_info(:work, state) do
      do_clean_subtitles()
      schedule_work()
      {:noreply, state}
    end

    def do_clean_subtitles() do
      Logger.debug("cleaning subtitles...")

      expiry_time =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-Subtitle.ttl_seconds())

      {deleted_count, _entities} =
        from(s in Subtitle,
          where:
            s.inserted_at <
              ^expiry_time
        )
        |> Repo.delete_all()

      Logger.info("deleted #{deleted_count} subtitles")
    end

    defp schedule_work() do
      # every minute, with a jitter of -10..30s (to prevent a constant load on the server)
      # it's not really a problem to make this run every minute, but i am thinking webscale.
      next_tick =
        case Mix.env() do
          :prod -> 60 * 1000 + Enum.random((-10 * 1000)..(30 * 1000))
          _ -> 10000
        end

      Process.send_after(self(), :work, next_tick)
    end
  end
end
