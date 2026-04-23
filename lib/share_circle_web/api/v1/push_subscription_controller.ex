defmodule ShareCircleWeb.Api.V1.PushSubscriptionController do
  use ShareCircleWeb, :controller

  alias ShareCircle.Notifications
  alias ShareCircleWeb.Api.V1.Response

  action_fallback ShareCircleWeb.Api.V1.FallbackController

  def create(conn, %{"subscription" => attrs}) do
    scope = conn.assigns.current_scope

    with {:ok, sub} <- Notifications.register_push_subscription(scope, attrs) do
      conn
      |> put_status(:created)
      |> Response.render_data(%{id: sub.id, endpoint: sub.endpoint})
    end
  end

  def delete(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope

    with {:ok, _sub} <- Notifications.delete_push_subscription(scope, id) do
      send_resp(conn, :no_content, "")
    end
  end
end
