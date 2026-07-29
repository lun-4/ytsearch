defmodule YtSearch.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger
  alias YtSearch.Tinycron

  def primaries() do
    Application.fetch_env!(:yt_search, :ecto_repos)
    # TODO decrease copypaste
    |> filter_repos_by_trending_role()
    |> then(fn repos ->
      cond do
        has_external_thumbnailer?() ->
          # Exclude thumbnail repos from main app
          Enum.reject(repos, fn repo ->
            to_string(repo) |> String.contains?("ThumbnailRepo")
          end)

        is_thumbnailer_node?() ->
          # Only thumbnail-related repos for thumbnailer
          Enum.filter(repos, fn repo ->
            repo_name = to_string(repo)

            String.contains?(repo_name, "ThumbnailRepo") or
              String.contains?(repo_name, "SearchSlotRepo") or
              String.contains?(repo_name, "SlotRepo") or
              String.contains?(repo_name, "ChannelSlotRepo")
          end)

        true ->
          # Monolith mode - all repos
          repos
      end
    end)
  end

  defp is_trending_node? do
    System.get_env("ROLE") == "trending"
  end

  defp has_external_trending? do
    case System.get_env("EXTERNAL_TRENDING_NODE") do
      nil -> false
      "" -> false
      _ -> true
    end
  end

  defp filter_repos_by_trending_role(repos) do
    case System.get_env("ROLE", "all") do
      "trending" ->
        Enum.filter(repos, fn repo ->
          repo == YtSearch.Data.TrendingRepo
        end)

      "primary" ->
        Enum.reject(repos, fn repo ->
          repo == YtSearch.Data.TrendingRepo
        end)

      _ ->
        if has_external_trending?() do
          Enum.reject(repos, fn repo ->
            repo == YtSearch.Data.TrendingRepo
          end)
        else
          repos
        end
    end
  end

  defp is_thumbnailer_node? do
    # Thumbnailer node has NODE_AUTH but no EXTERNAL_THUMBNAIL_NODE
    is_thumbnailer? = System.get_env("ROLE") == "thumbnailer"

    if is_thumbnailer? do
      # required
      if System.get_env("NODE_AUTH") == nil or System.get_env("EXTERNAL_THUMBNAIL_NODE") != nil do
        raise "thumbnailer invalid config, needs NODE_AUTH not nil and EXTERNAL_THUMBNAIL_NODE not nil"
      end

      true
    else
      false
    end
  end

  defp has_external_thumbnailer? do
    # Main app has EXTERNAL_THUMBNAIL_NODE configured
    case System.get_env("EXTERNAL_THUMBNAIL_NODE") do
      nil -> false
      "" -> false
      _ -> true
    end
  end

  defp repos() do
    Application.fetch_env!(:yt_search, :ecto_repos)
    |> filter_repos_by_trending_role()
    |> then(fn repos ->
      cond do
        has_external_thumbnailer?() ->
          IO.puts("has_external_thumbnailer? => true")
          # Exclude thumbnail repos from main app
          Enum.reject(repos, fn repo ->
            to_string(repo) |> String.contains?("ThumbnailRepo")
          end)

        is_thumbnailer_node?() ->
          IO.puts("is_thumbnailer_node? => true")
          # Only thumbnail-related repos for thumbnailer
          Enum.filter(repos, fn repo ->
            repo_name = to_string(repo)

            String.contains?(repo_name, "ThumbnailRepo") or
              String.contains?(repo_name, "SearchSlotRepo") or
              String.contains?(repo_name, "SlotRepo") or
              String.contains?(repo_name, "ChannelSlotRepo")
          end)

        true ->
          IO.puts("monolith mode")
          # Monolith mode - all repos
          repos
      end
    end)
    |> Enum.map(fn primary ->
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
    |> Enum.reduce(fn x, acc -> x ++ acc end)
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

  defp children_for(:thumbnailer) do
    # necessary processes for thumbnailer
    [
      # only _really_ endpoint since node api is http lol
      YtSearchWeb.Endpoint
    ] ++ thumbnail_children()
  end

  defp children_for(:trending) do
    [
      {Phoenix.PubSub, name: YtSearch.PubSub},
      # Endpoint needed for /api/node/view HTTP endpoint
      YtSearchWeb.Endpoint
    ]
  end

  # the processes necessary to do thumbnails
  defp thumbnail_children do
    [
      %{
        id: ThumbnailMutex,
        start: {Mutex, :start_link, [[name: ThumbnailMutex]]}
      },
      {Task.Supervisor, strategy: :one_for_one, name: YtSearch.ThumbnailSupervisor},
      YtSearch.Youtube.Thumbnail.Monitor
    ]
  end

  defp maybe_trending_children do
    # No extra children needed - trending views arrive via HTTP,
    # and Reporter runs via Tinycron
    []
  end

  @impl true
  def start(_type, _args) do
    role = System.get_env("ROLE", "all")
    Logger.info("Starting application with ROLE=#{role}")

    if is_trending_node?() do
      start_trending()
    else
      start_primary_or_all()
    end
  end

  defp start_trending do
    start_telemetry()

    children =
      [YtSearchWeb.Telemetry] ++
        repos() ++
        checkpointer() ++
        children_for(:trending) ++
        maybe_janitors()

    opts = [strategy: :one_for_one, name: YtSearch.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp start_primary_or_all do
    :erlang.system_flag(:microstate_accounting, true)

    # Conditional setup for thumbnails
    unless has_external_thumbnailer?() do
      File.mkdir_p!("thumbnails")
      # ETS table to track thumbnail download tasks
      :ets.new(:thumbnail_tasks, [:set, :public, :named_table, read_concurrency: true])
    end

    File.mkdir_p!("subtitles")

    children_before_repos =
      [
        # Start the Telemetry supervisor, wanted to be before repos
        # since repos need telemetry setup
        YtSearchWeb.Telemetry
      ] ++
        if is_thumbnailer_node?() do
          []
        else
          # hackney connection pool for the Piped micro-client, started before
          # repos so the primary/monolith roles that talk to Piped have it ready
          [:hackney_pool.child_spec(:yt_search_piped, timeout: 150_000, max_connections: 50)]
        end

    children_after_repos =
      if is_thumbnailer_node?() do
        children_for(:thumbnailer) ++ maybe_janitors()
      else
        [
          {Phoenix.PubSub, name: YtSearch.PubSub},
          YtSearchWeb.Endpoint,
          {Mutex, name: Mp4LinkMutex},
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
          YtSearch.CounterServer,
          {Task, &YtSearch.Counter.Seeder.run/0},
          {DynamicSupervisor, strategy: :one_for_one, name: YtSearch.MetadataSupervisor},
          {Registry, keys: :unique, name: YtSearch.MetadataWorkers},
          {Registry, keys: :unique, name: YtSearch.MetadataExtractors},
          {Task.Supervisor, strategy: :one_for_one, name: YtSearch.SlotMetadataSupervisor}
        ] ++
          if(has_external_thumbnailer?(), do: [], else: thumbnail_children()) ++
          maybe_trending_children() ++
          maybe_janitors()
      end

    children = children_before_repos ++ repos() ++ checkpointer() ++ children_after_repos

    start_telemetry()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: YtSearch.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def janitor_specs do
    [
      [YtSearch.Subtitle.Cleaner, [every: 8 * 60, jitter: -60..60]],
      [YtSearch.Mp4Link.Janitor, [every: 20 * 60, jitter: (-2 * 60)..(5 * 60)]],
      [YtSearch.Thumbnail.Janitor, [every: 2 * 60, jitter: 60..(1 * 60)]],
      [YtSearch.Repo.Janitor, [every: 60, jitter: -30..30]],
      [YtSearch.Chapters.Cleaner, [every: 1 * 60 * 60, jitter: (-20 * 60)..(20 * 60)]],
      [YtSearch.AudioConfig.Cleaner, [every: 30 * 60, jitter: -60..60]],
      [YtSearch.Sponsorblock.Segments.Cleaner, [every: 10 * 60, jitter: -60..60]]
    ]
  end

  def base_task_specs do
    [
      [YtSearch.Repo.FreelistMeter, [every: 30, jitter: -10..30]],
      [YtSearch.Repo.Analyzer, [every: 3 * 60 * 60, jitter: (-20 * 60)..(20 * 60)]]
    ]
  end

  def periodic_task_specs("primary") do
    [
      [YtSearch.SlotUtilities.UsageMeter, [every: 60, jitter: (-3 * 60)..(3 * 60)]]
    ]
  end

  def periodic_task_specs("trending") do
    [
      # [YtSearch.Trending.Reporter, [every: 3 * 60 * 60, jitter: 0..0]]
    ]
  end

  def periodic_task_specs("all") do
    periodic_task_specs("primary") ++ periodic_task_specs("trending")
  end

  # Default for thumbnailer or other roles
  def periodic_task_specs(_), do: []

  defp checkpointer do
    # in tests the SQL sandbox owns the connections; a terminate-time
    # checkpoint would only raise ownership errors
    if Mix.env() == :test do
      []
    else
      [YtSearch.Repo.Checkpointer]
    end
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

    role = System.get_env("ROLE", "all")

    periodic_tasks =
      if enable_periodic do
        (base_task_specs() ++ periodic_task_specs(role))
        |> Enum.map(fn [module, opts] ->
          Tinycron.new(module, opts)
        end)
      else
        []
      end

    janitor_tasks =
      if role in ["primary", "all"] and enable_janitor do
        specs =
          cond do
            is_thumbnailer_node?() ->
              # Only thumbnail janitor for thumbnailer
              [[YtSearch.Thumbnail.Janitor, [every: 2 * 60, jitter: 60..(1 * 60)]]]

            has_external_thumbnailer?() ->
              # All janitors except thumbnail (thumbnail runs on thumbnailer)
              janitor_specs()
              |> Enum.reject(fn [module, _] -> module == YtSearch.Thumbnail.Janitor end)

            true ->
              # Monolith mode - all janitors
              janitor_specs()
          end

        specs
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
    YtSearchWeb.GiftDropController.GiftCounter.setup()
    YtSearchWeb.FallController.FallCounter.setup()
    YtSearch.Repo.FreelistMeter.Gauge.setup()
    YtSearch.SlotUtilities.RecycledSlotAge.setup()
    YtSearch.CounterServer.Metrics.setup()
    YtSearch.MetadataExtractor.Worker.TaskLatency.setup()
    YtSearch.Thumbnail.Atlas.InvalidRatio.setup()
    YtSearch.Youtube.Thumbnail.TaskCounter.setup()

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
