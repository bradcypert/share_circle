defmodule ShareCircleWorkers.DeliverNotification do
  @moduledoc """
  Oban worker that delivers a notification via email and/or web push,
  based on the recipient's preferences.
  """

  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias ShareCircle.Notifications
  alias ShareCircle.Notifications.Notification
  alias ShareCircle.Push
  alias ShareCircle.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"notification_id" => id}}) do
    notification = Repo.get!(Notification, id) |> Repo.preload(:recipient_user)

    channels =
      Notifications.get_channels(
        notification.recipient_user_id,
        notification.family_id,
        notification.kind
      )

    if Map.get(channels, "email") do
      deliver_email(notification)
    end

    if Map.get(channels, "push") do
      deliver_push(notification)
    end

    :ok
  end

  defp deliver_email(notification) do
    user = notification.recipient_user

    ShareCircle.NotificationMailer.notification_email(user, notification)
    |> ShareCircle.Mailer.deliver()
  end

  defp deliver_push(notification) do
    subs = Notifications.list_push_subscriptions(notification.recipient_user_id)
    payload = build_push_payload(notification)

    Enum.each(subs, fn sub ->
      Push.send(
        %{endpoint: sub.endpoint, p256dh_key: sub.p256dh_key, auth_key: sub.auth_key},
        payload
      )
    end)
  end

  defp build_push_payload(notification) do
    %{
      title: notification_title(notification.kind),
      body: Map.get(notification.payload, "preview", ""),
      data: %{
        notification_id: notification.id,
        kind: notification.kind,
        subject_type: notification.subject_type,
        subject_id: notification.subject_id
      }
    }
  end

  defp notification_title("new_post"), do: "New post in your family"
  defp notification_title("new_comment"), do: "New comment on your post"
  defp notification_title("new_message"), do: "New message"
  defp notification_title("reaction"), do: "Someone reacted to your post"
  defp notification_title("event_created"), do: "New family event"
  defp notification_title("rsvp_changed"), do: "RSVP updated"
  defp notification_title("member_joined"), do: "New family member"
  defp notification_title(_), do: "New notification"
end
