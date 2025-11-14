defmodule YtSearch.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger
  alias YtSearch.Tinycron

  def primaries() do
    role = System.get_env("ROLE", "all")

    if role in ["all", "primary"] do
      Application.fetch_env!(:yt_search, :ecto_repos)
      |> Enum.reject(fn r -> r == YtSearch.Data.TrendingRepo end)
    else
      [YtSearch.Data.TrendingRepo]
    end
  end

  defp filter_repos_by_role(repos, "primary") do
    # everything but Trending
    Enum.reject(repos, fn repo ->
      repo == YtSearch.Data.TrendingRepo
    end)
  end

  defp filter_repos_by_role(repos, "trending") do
    # only Trending
    Enum.filter(repos, fn repo ->
      repo == YtSearch.Data.TrendingRepo
    end)
  end

  defp filter_repos_by_role(repos, "all") do
    # both
    repos
  end

  @impl true
  def start(_type, _args) do
    role = System.get_env("ROLE", "all")
    Logger.info("Starting application with ROLE=#{role}")

    children = children_for(role) |> Enum.reject(&is_nil/1)

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: YtSearch.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp children_for("primary") do
    setup_primary_environment()
    start_telemetry()

    base_children() ++ repos_for("primary") ++ primary_service_children() ++ maybe_janitors()
  end

  defp children_for("trending") do
    cluster_and_pubsub() ++ repos_for("trending") ++ [YtSearch.Trending]
  end

  defp children_for("all") do
    setup_primary_environment()
    start_telemetry()

    base_children() ++
      repos_for("all") ++ primary_service_children() ++ [YtSearch.Trending] ++ maybe_janitors()
  end

  defp children_for(unknown) do
    raise "unknown ROLE: #{unknown}"
  end

  defp base_children do
    [
      # Telemetry
      YtSearchWeb.Telemetry
    ] ++ cluster_and_pubsub()
  end

  defp cluster_and_pubsub do
    [
      # Cluster & PubSub (needed for distributed communication)
      {Cluster.Supervisor, [topologies(), [name: YtSearch.ClusterSupervisor]]},
      {Phoenix.PubSub, name: YtSearch.PhoenixPubSub}
    ]
  end

  defp primary_service_children do
    [
      # Web server
      YtSearchWeb.Endpoint,
      # Mutexes for coordinating work
      {Mutex, name: Mp4LinkMutex},
      %{id: ThumbnailMutex, start: {Mutex, :start_link, [[name: ThumbnailMutex]]}},
      %{id: SubtitleMutex, start: {Mutex, :start_link, [[name: SubtitleMutex]]}},
      %{id: SearchMutex, start: {Mutex, :start_link, [[name: SearchMutex]]}},
      %{
        id: PlaylistEntryCreatorMutex,
        start: {Mutex, :start_link, [[name: PlaylistEntryCreatorMutex]]}
      },
      # Cache and state
      {Cachex, name: :tabs},
      YtSearch.CounterServer,
      # Work supervisors
      {DynamicSupervisor, strategy: :one_for_one, name: YtSearch.MetadataSupervisor},
      {Task.Supervisor, strategy: :one_for_one, name: YtSearch.ThumbnailSupervisor},
      {Task.Supervisor, strategy: :one_for_one, name: YtSearch.SlotMetadataSupervisor},
      YtSearch.Youtube.Thumbnail.Monitor,
      # Registries
      {Registry, keys: :unique, name: YtSearch.MetadataWorkers},
      {Registry, keys: :unique, name: YtSearch.MetadataExtractors}
    ]
  end

  defp setup_primary_environment do
    :erlang.system_flag(:microstate_accounting, true)
    File.mkdir_p!("thumbnails")
    File.mkdir_p!("subtitles")
    # ETS table to track thumbnail download tasks
    :ets.new(:thumbnail_tasks, [:set, :public, :named_table, read_concurrency: true])
  end

  defp repos_for(role) do
    Application.fetch_env!(:yt_search, :ecto_repos)
    |> filter_repos_by_role(role)
    |> Enum.flat_map(fn primary ->
      primary
      |> to_string
      |> then(fn
        "Elixir.YtSearch.Data" <> _ ->
          spec = primary.repo_spec()
          [primary] ++ spec.read_replicas ++ spec.dedicated_replicas

        _ ->
          []
      end)
    end)
    |> Enum.map(fn repo ->
      case Application.fetch_env(:yt_search, repo) do
        :error ->
          raise RuntimeError, "Repo #{repo} not configured"

        {:ok, cfg} ->
          if Access.get(cfg, :database) == nil do
            raise RuntimeError, "Repo #{repo} not configured. missing database"
          end

          repo
      end
    end)
  end

  defp topologies do
    Application.get_env(:yt_search, :topologies, [])
  end

  def janitor_specs do
    [
      [YtSearch.Subtitle.Cleaner, [every: 8 * 60, jitter: -60..60]],
      [YtSearch.Mp4Link.Janitor, [every: 20 * 60, jitter: (-2 * 60)..(5 * 60)]],
      [YtSearch.Thumbnail.Janitor, [every: 2 * 60, jitter: 60..(1 * 60)]],
      [YtSearch.Repo.Janitor, [every: 60, jitter: -30..30]],
      [YtSearch.Chapters.Cleaner, [every: 1 * 60 * 60, jitter: (-20 * 60)..(20 * 60)]],
      [YtSearch.AudioConfig.Cleaner, [every: 30 * 60, jitter: -60..60]]
    ]
  end

  def periodic_task_specs do
    [
      [YtSearch.SlotUtilities.UsageMeter, [every: 60, jitter: (-3 * 60)..(3 * 60)]],
      [YtSearch.Repo.FreelistMeter, [every: 30, jitter: -10..30]],
      [YtSearch.Repo.Analyzer, [every: 3 * 60 * 60, jitter: (-20 * 60)..(20 * 60)]]
    ]
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
        Application.get_env(:yt_search, YtSearch.Constants)[:enable_periodic_janitors]
      end

    periodic_tasks =
      if enable_periodic do
        periodic_task_specs()
        |> Enum.map(fn [module, opts] ->
          Tinycron.new(module, opts)
        end)
      else
        []
      end

    janitor_tasks =
      if enable_janitor do
        janitor_specs()
        |> Enum.map(fn [module, opts] ->
          Tinycron.new(module, opts)
        end)
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
    YtSearch.Youtube.ErrorVideoCounter.setup()
    YtSearch.Youtube.UnavailableVideoCounter.setup()
    YtSearch.SlotUtilities.UsageMeter.Gauge.setup()
    YtSearchWeb.HelloController.BuildReporter.setup()
    YtSearchWeb.AngelOfDeathController.ErrorCounter.setup()
    YtSearch.Repo.FreelistMeter.Gauge.setup()
    YtSearch.SlotUtilities.RecycledSlotAge.setup()
    YtSearch.CounterServer.Metrics.setup()
    YtSearch.MetadataExtractor.Worker.TaskLatency.setup()
    YtSearch.Thumbnail.Atlas.InvalidRatio.setup()
    YtSearch.Youtube.Thumbnail.TaskCounter.setup()

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
