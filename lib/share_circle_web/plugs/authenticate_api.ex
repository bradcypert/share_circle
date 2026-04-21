defmodule ShareCircleWeb.Plugs.AuthenticateApi do
  @moduledoc """
  Authenticates API requests via Bearer token.

  Expects an `Authorization: Bearer <token>` header. Looks up the raw token
  (hashed with SHA-256) in users_tokens with context "api". On success,
  puts a Scope with the authenticated user into conn.assigns.current_scope.
  On failure, halts with 401.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias ShareCircle.Accounts
  alias ShareCircle.Accounts.Scope

  def init(opts), do: opts

  def call(conn, _opts) do
    case bearer_token(conn) do
      {:ok, token} ->
        case Accounts.get_user_by_api_token(token) do
          %{} = user ->
            scope = %{Scope.for_user(user) | request_id: conn.assigns[:request_id]}
            assign(conn, :current_scope, scope)

          nil ->
            unauthorized(conn)
        end

      :error ->
        unauthorized(conn)
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> {:ok, token}
      _ -> :error
    end
  end

  defp unauthorized(conn) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: %{code: "unauthorized", message: "Invalid or missing API token"}})
    |> halt()
  end
end
