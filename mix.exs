defmodule YtSearch.MixProject do
  use Mix.Project

  def project do
    [
      app: :yt_search,
      version: "0.1.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {YtSearch.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.7.6"},
      {:phoenix_ecto, "~> 4.4"},
      {:ecto_sql, "~> 3.10"},
      {:ecto_sqlite3, ">= 0.0.0"},
      {:phoenix_live_dashboard, "~> 0.8.0"},
      {:finch, "~> 0.8"},
      {:swoosh, "~> 1.3"},
      {:httpoison, "~> 2.0"},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.20"},
      {:jason, "~> 1.2"},
      {:mock, "~> 0.3.8"},
      {:plug_cowboy, "~> 2.5"},
      {:mutex, "~>1.3"},
      {:mogrify, "~> 0.9.3"},
      {:temp, "~> 0.4"},
      {:cachex, "~> 3.6"},
      {:prometheus, "~> 4.6"},
      {:prometheus_ex,
       git: "https://github.com/lanodan/prometheus.ex.git",
       branch: "fix/elixir-1.14",
       override: true},
      {:prometheus_plugs, "~> 1.1"},
      {:prometheus_phoenix, "~> 1.3"},
      # Note: once `prometheus_phx` is integrated into `prometheus_phoenix`, remove the former:
      {:prometheus_phx,
       git: "https://git.pleroma.social/pleroma/elixir-libraries/prometheus-phx.git",
       branch: "no-logging"},
      {:prometheus_ecto, "~> 1.4"},
      {:erlexec, "~> 2.0"},
      {:hammer, "~> 6.1"},
      {:tesla, "~> 1.7"},
      {:hackney, "~> 1.18"},
      {:recon, "~> 2.5"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_machina, "~> 2.4", only: :test}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
