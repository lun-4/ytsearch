defmodule YtSearch.Constants do
  alias YtSearch.Tinycron
  require Logger

  def cron_callback(specs, enabled?) do
    specs
    |> Enum.map(fn [module, _] ->
      noop? = not enabled?

      if noop? do
        Logger.info("disabling cron #{inspect(module)}")
      else
        Logger.info("enabling cron #{inspect(module)}")
      end

      Tinycron.noop(module, noop?)
    end)
  end

  def apply(new_constants) do
    cron_callback(YtSearch.Application.janitor_specs(), new_constants[:enable_periodic_janitors])

    cron_callback(
      YtSearch.Application.periodic_task_specs(),
      new_constants[:enable_periodic_tasks]
    )

    Application.put_env(:yt_search, __MODULE__, new_constants)
  end
end
