defmodule ShareCircleWeb.Api.V1.AuthController do
  use ShareCircleWeb, :controller

  alias ShareCircle.Accounts
  alias ShareCircle.Accounts.UserToken
  alias ShareCircleWeb.Api.V1.{Response, UserJSON}

  action_fallback ShareCircleWeb.Api.V1.FallbackController

  # TODO: Enforce confirmed_at — unconfirmed users can currently access all endpoints.
  # See GitHub issue tracker.

  # POST /api/v1/auth/register
  def register(conn, %{"user" => params}) do
    with {:ok, user} <- Accounts.register_user_with_password(params) do
      token = Accounts.generate_user_api_token(user)

      # Best-effort confirmation email — don't fail registration if it errors
      Accounts.deliver_user_confirmation_instructions(user, fn t ->
        url(~p"/api/v1/auth/email/confirm?token=#{t}")
      end)

      conn
      |> put_status(:created)
      |> Response.render_data(%{user: UserJSON.render(user), token: token})
    end
  end

  # POST /api/v1/auth/login
  def login(conn, %{"email" => email, "password" => password}) do
    case Accounts.get_user_by_email_and_password(email, password) do
      nil ->
        Response.render_error(
          conn,
          :unauthorized,
          "invalid_credentials",
          "Invalid email or password"
        )

      user ->
        token = Accounts.generate_user_api_token(user)
        Response.render_data(conn, %{user: UserJSON.render(user), token: token})
    end
  end

  # POST /api/v1/auth/logout
  def logout(conn, _params) do
    Accounts.delete_user_api_token(conn.assigns.api_token)
    send_resp(conn, :no_content, "")
  end

  # POST /api/v1/auth/refresh
  def refresh(conn, _params) do
    user = conn.assigns.current_scope.user
    Accounts.delete_user_api_token(conn.assigns.api_token)
    token = Accounts.generate_user_api_token(user)
    Response.render_data(conn, %{token: token})
  end

  # POST /api/v1/auth/password/reset/request
  def request_password_reset(conn, %{"email" => email}) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_reset_password_instructions(user, fn t ->
        url(~p"/api/v1/auth/password/reset/confirm?token=#{t}")
      end)
    end

    # Always 204 — don't reveal whether the email exists
    send_resp(conn, :no_content, "")
  end

  # POST /api/v1/auth/password/reset/confirm
  def confirm_password_reset(conn, %{"token" => token, "password" => password}) do
    case Accounts.reset_user_password(token, %{password: password}) do
      {:ok, {user, _}} ->
        new_token = Accounts.generate_user_api_token(user)
        Response.render_data(conn, %{user: UserJSON.render(user), token: new_token})

      {:error, :invalid_or_expired_token} ->
        Response.render_error(
          conn,
          :unprocessable_entity,
          "invalid_token",
          "Token is invalid or has expired"
        )

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  # POST /api/v1/auth/email/confirm
  def confirm_email(conn, %{"token" => token}) do
    case Accounts.confirm_user_email(token) do
      {:ok, user} ->
        Response.render_data(conn, UserJSON.render(user))

      {:error, :invalid_or_expired_token} ->
        Response.render_error(
          conn,
          :unprocessable_entity,
          "invalid_token",
          "Token is invalid or has expired"
        )
    end
  end

  # POST /api/v1/auth/email/resend
  def resend_confirmation(conn, _params) do
    user = conn.assigns.current_scope.user

    case Accounts.deliver_user_confirmation_instructions(user, fn t ->
           url(~p"/api/v1/auth/email/confirm?token=#{t}")
         end) do
      {:ok, _} ->
        send_resp(conn, :no_content, "")

      {:error, :already_confirmed} ->
        Response.render_error(
          conn,
          :unprocessable_entity,
          "already_confirmed",
          "Email is already confirmed"
        )
    end
  end

  # GET /api/v1/auth/sessions
  def list_sessions(conn, _params) do
    tokens = Accounts.list_user_api_tokens(conn.assigns.current_scope.user)
    Response.render_data(conn, Enum.map(tokens, &session_json/1))
  end

  # DELETE /api/v1/auth/sessions/:id
  def delete_session(conn, %{"id" => id}) do
    with {:ok, _} <- Accounts.delete_user_api_token_by_id(conn.assigns.current_scope.user, id) do
      send_resp(conn, :no_content, "")
    end
  end

  defp session_json(%UserToken{} = t), do: %{id: t.id, inserted_at: t.inserted_at}
end
