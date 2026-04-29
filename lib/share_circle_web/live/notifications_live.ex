defmodule ShareCircleWeb.NotificationsLive do
  use ShareCircleWeb, :live_view

  alias ShareCircle.Notifications
  alias ShareCircle.PubSub

  @impl true
  def mount(params, _session, socket) do
    scope = socket.assigns.current_scope

    if connected?(socket) do
      PubSub.subscribe(PubSub.user_topic(scope.user.id))
    end

    notifications = Notifications.list_notifications(scope)
    unread = Notifications.unread_count(scope)
    vapid_public_key = Application.get_env(:share_circle, :vapid_public_key)

    {:ok,
     socket
     |> assign(:notifications, notifications)
     |> assign(:unread_count, unread)
     |> assign(:back_family_id, params["family_id"])
     |> assign(:vapid_public_key, vapid_public_key)
     |> assign(:push_subscribed, false)}
  end

  @impl true
  def handle_event(
        "push_subscribed",
        %{"endpoint" => endpoint, "p256dh_key" => p256dh, "auth_key" => auth},
        socket
      ) do
    attrs = %{"endpoint" => endpoint, "p256dh_key" => p256dh, "auth_key" => auth}

    case ShareCircle.Notifications.register_push_subscription(socket.assigns.current_scope, attrs) do
      {:ok, _sub} -> {:noreply, assign(socket, :push_subscribed, true)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not enable push notifications.")}
    end
  end

  def handle_event("push_already_subscribed", _params, socket) do
    {:noreply, assign(socket, :push_subscribed, true)}
  end

  def handle_event("mark_read", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    case Notifications.mark_read(scope, id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> update(:notifications, &mark_notification_read(&1, id))
         |> update(:unread_count, &max(&1 - 1, 0))}

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

  defp mark_notification_read(notifications, id) do
    Enum.map(notifications, fn n ->
      if n.id == id, do: %{n | read_at: DateTime.utc_now()}, else: n
    end)
  end

  defp notification_text(%{kind: kind, actor_user: actor}) do
    notification_message(kind, actor_name(actor))
  end

  defp actor_name(nil), do: "Someone"
  defp actor_name(%{display_name: name}), do: name

  defp notification_message("new_post", name), do: "#{name} shared a new post"
  defp notification_message("new_comment", name), do: "#{name} commented on a post"
  defp notification_message("new_message", name), do: "#{name} sent a message"
  defp notification_message("reaction", name), do: "#{name} reacted to your post"
  defp notification_message("event_created", name), do: "#{name} added a new event"
  defp notification_message("rsvp_changed", name), do: "#{name} updated their RSVP"
  defp notification_message("member_joined", name), do: "#{name} joined the family"
  defp notification_message(_, name), do: "New notification from #{name}"

  defp format_time(dt) do
    Calendar.strftime(dt, "%b %-d at %-I:%M %p")
  end
end
