defmodule YtSearchWeb.Router do
  use YtSearchWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", YtSearchWeb do
    pipe_through :api
  end

  scope "/api/v1", YtSearchWeb do
    get("/search", SearchController, :search)
    get("/s/:slot_id", SlotController, :fetch_video)
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:yt_search, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard", metrics: YtSearchWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
