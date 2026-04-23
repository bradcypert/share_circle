defmodule ShareCircleWeb.Api.V1.NotificationPreferenceController do
  use ShareCircleWeb, :controller

  alias ShareCircle.Notifications
  alias ShareCircleWeb.Api.V1.Response

  action_fallback ShareCircleWeb.Api.V1.FallbackController

  def index(conn, _params) do
    scope = conn.assigns.current_scope
    prefs = Notifications.list_preferences(scope)

    data = Enum.map(prefs, fn p ->
      %{id: p.id, kind: p.kind, family_id: p.family_id, channels: p.channels}
    end)

    Response.render_collection(conn, data, %{})
  end

  def update(conn, %{"kind" => kind, "channels" => channels}) do
    scope = conn.assigns.current_scope

    with {:ok, pref} <- Notifications.update_preference(scope, kind, channels) do
      Response.render_data(conn, %{
        id: pref.id,
        kind: pref.kind,
        family_id: pref.family_id,
        channels: pref.channels
      })
    end
  end
end
