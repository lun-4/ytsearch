defmodule YtSearch.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      YtSearchWeb.Telemetry,
      # Start the Ecto repository
      YtSearch.Repo,
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
      {Cachex, name: :tabs},
      YtSearch.SlotUtilities.UsageMeter,
      YtSearch.Subtitle.Cleaner
    ]

    start_telemetry()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: YtSearch.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp start_telemetry do
    require Prometheus.Registry

    if Application.get_env(:prometheus, YtSearch.Repo.Instrumenter) do
      :ok =
        :telemetry.attach(
          "prometheus-ecto",
          [:pleroma, :repo, :query],
          &YtSearch.Repo.Instrumenter.handle_event/4,
          %{}
        )

      YtSearch.Repo.Instrumenter.setup()
    end

    YtSearchWeb.Endpoint.MetricsExporter.setup()
    YtSearchWeb.Endpoint.PipelineInstrumenter.setup()
    YtSearch.Youtube.CallCounter.setup()
    YtSearch.SlotUtilities.RerollCounter.setup()
    YtSearch.SlotUtilities.UsageMeter.Gauge.setup()

    # Note: disabled until prometheus-phx is integrated into prometheus-phoenix:
    # YtSearchWeb.Endpoint.Instrumenter.setup()
    PrometheusPhx.setup()
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    YtSearchWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
