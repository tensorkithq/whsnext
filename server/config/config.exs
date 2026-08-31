# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :whn,
  ecto_repos: [Whn.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :whn, WhnWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: WhnWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Whn.PubSub,
  live_view: [signing_salt: "UmhCX163"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# fal_ex builds Tesla clients without naming an adapter; pin the hackney
# adapter it ships with instead of Tesla's :httpc fallback. recv_timeout
# matches fal_ex's 300s request timeout — hackney's 5s default kills
# generation calls mid-flight. Tesla is only used by fal_ex — see
# Whn.Fal.FalExImpl.
config :tesla, adapter: {Tesla.Adapter.Hackney, recv_timeout: 300_000}

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
