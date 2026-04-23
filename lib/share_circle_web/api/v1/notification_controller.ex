defmodule ShareCircleWeb.Api.V1.NotificationController do
  use ShareCircleWeb, :controller

  alias ShareCircle.Notifications
  alias ShareCircleWeb.Api.V1.{NotificationJSON, Response}

  action_fallback ShareCircleWeb.Api.V1.FallbackController

  def index(conn, params) do
    scope = conn.assigns.current_scope
    opts = [unread_only: params["unread_only"] == "true"]
    notifications = Notifications.list_notifications(scope, opts)
    unread = Notifications.unread_count(scope)
    Response.render_collection(conn, Enum.map(notifications, &NotificationJSON.render/1), %{unread_count: unread})
  end

  def read(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope

    with {:ok, notification} <- Notifications.mark_read(scope, id) do
      Response.render_data(conn, NotificationJSON.render(notification))
    end
  end

  def read_all(conn, _params) do
    scope = conn.assigns.current_scope
    {:ok, count} = Notifications.mark_all_read(scope)
    Response.render_data(conn, %{marked_read: count})
  end
end
