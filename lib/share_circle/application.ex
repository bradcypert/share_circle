defmodule ShareCircle.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ShareCircleWeb.Telemetry,
      ShareCircle.Repo,
      {DNSCluster, query: Application.get_env(:share_circle, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: ShareCircle.PubSub},
      # Start a worker by calling: ShareCircle.Worker.start_link(arg)
      # {ShareCircle.Worker, arg},
      # Start to serve requests, typically the last entry
      ShareCircleWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ShareCircle.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ShareCircleWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
