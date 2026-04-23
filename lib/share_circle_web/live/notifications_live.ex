defmodule ShareCircleWeb.NotificationsLive do
  use ShareCircleWeb, :live_view

  alias ShareCircle.Notifications
  alias ShareCircle.PubSub

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if connected?(socket) do
      PubSub.subscribe(PubSub.user_topic(scope.user.id))
    end

    notifications = Notifications.list_notifications(scope)
    unread = Notifications.unread_count(scope)

    {:ok,
     socket
     |> assign(:notifications, notifications)
     |> assign(:unread_count, unread)}
  end

  @impl true
  def handle_event("mark_read", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    case Notifications.mark_read(scope, id) do
      {:ok, _} ->
        notifications =
          Enum.map(socket.assigns.notifications, fn n ->
            if n.id == id, do: %{n | read_at: DateTime.utc_now()}, else: n
          end)

        {:noreply,
         socket
         |> assign(:notifications, notifications)
         |> assign(:unread_count, max(socket.assigns.unread_count - 1, 0))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("mark_all_read", _params, socket) do
    scope = socket.assigns.current_scope
    {:ok, _} = Notifications.mark_all_read(scope)
    now = DateTime.utc_now()

    notifications =
      Enum.map(socket.assigns.notifications, fn n ->
        if is_nil(n.read_at), do: %{n | read_at: now}, else: n
      end)

    {:noreply,
     socket
     |> assign(:notifications, notifications)
     |> assign(:unread_count, 0)}
  end

  @impl true
  def handle_info({:notification_created, %{notification: notification}}, socket) do
    {:noreply,
     socket
     |> update(:notifications, &[notification | &1])
     |> update(:unread_count, &(&1 + 1))}
  end

  def handle_info({:notifications_all_read, _}, socket) do
    now = DateTime.utc_now()

    notifications =
      Enum.map(socket.assigns.notifications, fn n ->
        if is_nil(n.read_at), do: %{n | read_at: now}, else: n
      end)

    {:noreply,
     socket
     |> assign(:notifications, notifications)
     |> assign(:unread_count, 0)}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  defp notification_text(%{kind: kind, actor_user: actor}) do
    actor_name = if actor, do: actor.display_name, else: "Someone"

    case kind do
      "new_post" -> "#{actor_name} shared a new post"
      "new_comment" -> "#{actor_name} commented on a post"
      "new_message" -> "#{actor_name} sent a message"
      "reaction" -> "#{actor_name} reacted to your post"
      "event_created" -> "#{actor_name} added a new event"
      "rsvp_changed" -> "#{actor_name} updated their RSVP"
      "member_joined" -> "#{actor_name} joined the family"
      _ -> "New notification from #{actor_name}"
    end
  end

  defp format_time(dt) do
    Calendar.strftime(dt, "%b %-d at %-I:%M %p")
  end
end
