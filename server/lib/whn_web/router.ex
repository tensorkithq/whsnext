defmodule WhnWeb.Router do
  use WhnWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", WhnWeb do
    pipe_through :api
  end
end
