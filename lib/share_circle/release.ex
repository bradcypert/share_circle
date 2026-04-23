defmodule ShareCircle.Release do
  @moduledoc """
  Release tasks for running database migrations outside of Mix.

  Used in Docker deployments where Mix is not available:

      # Run all pending migrations
      bin/share_circle eval "ShareCircle.Release.migrate()"

      # Roll back to a specific version
      bin/share_circle eval "ShareCircle.Release.rollback(ShareCircle.Repo, 20260420135605)"
  """

  @app :share_circle

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  defp load_app, do: Application.load(@app)
end
