defmodule ShareCircleWeb.Api.V1.RsvpController do
  use ShareCircleWeb, :controller

  alias ShareCircle.Calendar
  alias ShareCircleWeb.Api.V1.{Response, RsvpJSON}

  action_fallback ShareCircleWeb.Api.V1.FallbackController

  def upsert(conn, %{"event_id" => event_id, "rsvp" => attrs}) do
    scope = conn.assigns.current_scope

    with {:ok, rsvp} <- Calendar.upsert_rsvp(scope, event_id, attrs) do
      Response.render_data(conn, RsvpJSON.render(rsvp))
    end
  end

  def show(conn, %{"event_id" => event_id}) do
    scope = conn.assigns.current_scope

    case Calendar.get_my_rsvp(scope, event_id) do
      nil -> send_resp(conn, :not_found, "")
      rsvp -> Response.render_data(conn, RsvpJSON.render(rsvp))
    end
  end
end
