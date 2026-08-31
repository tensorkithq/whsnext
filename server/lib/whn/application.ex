defmodule Whn.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      WhnWeb.Telemetry,
      Whn.Repo,
      {DNSCluster, query: Application.get_env(:whn, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Whn.PubSub},
      # Start a worker by calling: Whn.Worker.start_link(arg)
      # {Whn.Worker, arg},
      # Start to serve requests, typically the last entry
      WhnWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Whn.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    WhnWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
