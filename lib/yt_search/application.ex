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
      {Finch, name: YtSearch.Finch},
      # Start the Endpoint (http/https)
      YtSearchWeb.Endpoint,
      # Start a worker by calling: YtSearch.Worker.start_link(arg)
      # {YtSearch.Worker, arg}

      {Cachex, name: :mp4_links}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: YtSearch.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    YtSearchWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
