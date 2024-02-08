defmodule YtSearchWeb.Router do
  use YtSearchWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", YtSearchWeb do
    pipe_through :api
  end

  scope "/api/v5", YtSearchWeb do
    get("/search", SearchController, :search_by_text)
    get("/c/:channel_slot_id", SearchController, :fetch_channel)
    get("/p/:playlist_slot_id", SearchController, :fetch_playlist)
    get("/s/:slot_id", SlotController, :fetch_video)
    get("/sr/:slot_id", SlotController, :fetch_redirect)
    get("/tn/:slot_id", AtlasController, :fetch_single_thumbnail)
    get("/thumbnail_atlas/:search_slot_id", AtlasController, :fetch)
    get("/hello", HelloController, :hello)
    get("/hello/:build_number", HelloController, :hello)
    get("/aod/retry", AngelOfDeathController, :report_video_retry_error)
    get("/aod/retry:number", AngelOfDeathController, :report_video_retry_error)
    get("/aod/:error_id", AngelOfDeathController, :report_error)
  end

  # smaller url version of the api, this is a bodge for
  # - quest vrchat keyboard not having a cursor you can click on
  # - quest vrchat keyboard not actually scrolling properly when link is too long
  # - world url map has less bytes per url, which helps on overall world size
  scope "/a/5", YtSearchWeb do
    get("/s", SearchController, :search_by_text)
    get("/c/:channel_slot_id", SearchController, :fetch_channel)
    get("/p/:playlist_slot_id", SearchController, :fetch_playlist)
    get("/at/:search_slot_id", AtlasController, :fetch)
    get("/tn/:slot_id", AtlasController, :fetch_single_thumbnail)
    get("/sl/:slot_id", SlotController, :fetch_video)
    get("/qr/:slot_id", SlotController, :refresh)
    get("/sr/:slot_id", SlotController, :fetch_redirect)
    get("/sl/:slot_id/index.m3u8", SlotController, :fetch_stream_redirect)
    get("/aod/retry", AngelOfDeathController, :report_video_retry_error)
    get("/aod/retry:number", AngelOfDeathController, :report_video_retry_error)
    get("/aod/:error_id", AngelOfDeathController, :report_error)
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
