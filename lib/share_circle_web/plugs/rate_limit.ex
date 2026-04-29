defmodule ShareCircleWeb.Plugs.RateLimit do
  @moduledoc """
  Rate-limiting plug backed by ShareCircle.RateLimiter.

  Options:
  - `:bucket` — required, one of :auth, :write, :read, :upload

  Key strategy: uses the authenticated user's ID when available, falls back to remote IP.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias ShareCircle.Accounts.Scope
  alias ShareCircle.RateLimiter

  def init(opts) do
    bucket = Keyword.fetch!(opts, :bucket)
    %{bucket: bucket}
  end

  def call(conn, %{bucket: bucket}) do
    key = rate_limit_key(conn)

    case RateLimiter.check(bucket, key) do
      :ok ->
        conn

      {:error, :rate_limited} ->
        conn
        |> put_status(:too_many_requests)
        |> json(%{
          error: %{code: "rate_limited", message: "Too many requests. Please slow down."}
        })
        |> halt()
    end
  end

  defp rate_limit_key(%{assigns: %{current_scope: %Scope{user: user}}}) when not is_nil(user) do
    {:user, user.id}
  end

  defp rate_limit_key(conn) do
    {:ip, conn.remote_ip}
  end
end
