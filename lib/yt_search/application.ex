defmodule YtSearch.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger
  alias YtSearch.Tinycron

  @impl true
  def start(_type, _args) do
    File.mkdir_p!("thumbnails")

    children =
      [
        # Start the Telemetry supervisor
        YtSearchWeb.Telemetry,
        # Start the Ecto repository
        YtSearch.Repo,
        YtSearch.Repo.Replica1,
        YtSearch.Repo.Replica2,
        YtSearch.Repo.Replica3,
        YtSearch.Repo.Replica4,
        YtSearch.Repo.Replica5,
        YtSearch.Repo.Replica6,
        YtSearch.Repo.Replica7,
        YtSearch.Repo.Replica8,
        YtSearch.Repo.ThumbnailReplica,

        # Start the PubSub system
        {Phoenix.PubSub, name: YtSearch.PubSub},
        # Start Finch
        # {Finch, name: YtSearch.Finch},
        # Start the Endpoint (http/https)
        YtSearchWeb.Endpoint,
        # Start a worker by calling: YtSearch.Worker.start_link(arg)
        # {YtSearch.Worker, arg}
        {Mutex, name: Mp4LinkMutex},
        %{
          id: ThumbnailMutex,
          start: {Mutex, :start_link, [[name: ThumbnailMutex]]}
        },
        %{
          id: SubtitleMutex,
          start: {Mutex, :start_link, [[name: SubtitleMutex]]}
        },
        %{
          id: SearchMutex,
          start: {Mutex, :start_link, [[name: SearchMutex]]}
        },
        %{
          id: PlaylistEntryCreatorMutex,
          start: {Mutex, :start_link, [[name: PlaylistEntryCreatorMutex]]}
        },
        {Cachex, name: :tabs},
        {DynamicSupervisor, strategy: :one_for_one, name: YtSearch.MetadataSupervisor},
        {Task.Supervisor, strategy: :one_for_one, name: YtSearch.ThumbnailSupervisor},
        {Registry, keys: :unique, name: YtSearch.MetadataWorkers},
        {Registry, keys: :unique, name: YtSearch.MetadataExtractors},
        {Registry, keys: :unique, name: YtSearch.SlotWriters},
        {ExHashRing.Ring, name: YtSearch.SlotWriterRing}
      ] ++ maybe_janitors() ++ writer_pool()

    start_telemetry()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: YtSearch.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp writer_pool do
    1..10
    |> Enum.map(fn id ->
      %{
        id: "slot_writer_#{id}",
        start:
          {YtSearch.SlotWriter, :start_link,
           [id, [name: {:via, Registry, {YtSearch.SlotWriters, "writer_#{id}", :self}}]]}
      }
    end)
  end

  defp maybe_janitors do
    enable_periodic =
      if Mix.env() == :test do
        false
      else
        Application.get_env(:yt_search, YtSearch.Constants)[:enable_periodic_tasks]
      end

    enable_janitor =
      if Mix.env() == :test do
        false
      else
        Application.get_env(:yt_search, YtSearch.Constants)[:enable_janitor_tasks]
      end

    periodic_tasks =
      if enable_periodic do
        [
          Tinycron.new(YtSearch.SlotUtilities.UsageMeter, every: 60, jitter: (-3 * 60)..(3 * 60)),
          Tinycron.new(YtSearch.Repo.FreelistMeter, every: 30, jitter: -10..30),
          Tinycron.new(YtSearch.Repo.Analyzer, every: 3 * 60 * 60, jitter: (-20 * 60)..(20 * 60))
        ]
      else
        []
      end

    janitor_tasks =
      if enable_janitor do
        [
          Tinycron.new(YtSearch.Subtitle.Cleaner, every: 8 * 60, jitter: -60..60),
          Tinycron.new(YtSearch.Mp4Link.Janitor, every: 20 * 60, jitter: (-2 * 60)..(5 * 60)),
          Tinycron.new(YtSearch.Thumbnail.Janitor, every: 3 * 60, jitter: (-2 * 60)..(2 * 60)),
          Tinycron.new(YtSearch.Repo.Janitor, every: 60, jitter: -30..30),
          Tinycron.new(YtSearch.Chapters.Cleaner,
            every: 1 * 60 * 60,
            jitter: (-20 * 60)..(20 * 60)
          )
        ]
      else
        []
      end

    periodic_tasks ++ janitor_tasks
  end

  defp start_telemetry do
    Logger.info("starting telemetry...")
    require Prometheus.Registry

    if Application.get_env(:prometheus, YtSearch.Repo.Instrumenter) do
      Logger.info("starting db telemetry...")

      :ok =
        :telemetry.attach(
          "prometheus-ecto",
          [:yt_search, :repo, :query],
          &YtSearch.Repo.Instrumenter.handle_event/4,
          %{}
        )

      YtSearch.Repo.Instrumenter.setup()
    end

    YtSearchWeb.Endpoint.MetricsExporter.setup()
    YtSearchWeb.Endpoint.PipelineInstrumenter.setup()
    YtSearch.Youtube.CallCounter.setup()
    YtSearch.Youtube.Latency.setup()
    YtSearch.SlotUtilities.UsageMeter.Gauge.setup()
    YtSearchWeb.HelloController.BuildReporter.setup()
    YtSearchWeb.AngelOfDeathController.ErrorCounter.setup()
    YtSearch.Repo.FreelistMeter.Gauge.setup()

    # Note: disabled until prometheus-phx is integrated into prometheus-phoenix:
    # YtSearchWeb.Endpoint.Instrumenter.setup()
    PrometheusPhx.setup()
    Logger.info("telemetry started!")
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    YtSearchWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
