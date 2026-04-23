defmodule ShareCircle.NotificationMailer do
  @moduledoc "Composes notification emails."

  import Swoosh.Email

  @from {"ShareCircle", "notifications@example.com"}

  def notification_email(user, notification) do
    new()
    |> to({user.display_name, user.email})
    |> from(@from)
    |> subject(subject_for(notification.kind))
    |> text_body(body_for(notification))
  end

  defp subject_for("new_post"), do: "New post in your family"
  defp subject_for("new_comment"), do: "Someone commented on a post"
  defp subject_for("new_message"), do: "You have a new message"
  defp subject_for("reaction"), do: "Someone reacted to your post"
  defp subject_for("event_created"), do: "New event added to your family calendar"
  defp subject_for("rsvp_changed"), do: "An RSVP was updated"
  defp subject_for("member_joined"), do: "A new member joined your family"
  defp subject_for(kind), do: "New notification: #{kind}"

  defp body_for(notification) do
    preview = Map.get(notification.payload, "preview", "")
    actor = if notification.actor_user, do: notification.actor_user.display_name, else: "Someone"

    """
    Hi #{notification.recipient_user.display_name},

    #{actor} #{action_text(notification.kind)}#{if preview != "", do: ":\n\n  #{preview}", else: "."}

    Log in to ShareCircle to see more.
    """
  end

  defp action_text("new_post"), do: "shared a new post"
  defp action_text("new_comment"), do: "commented on a post"
  defp action_text("new_message"), do: "sent you a message"
  defp action_text("reaction"), do: "reacted to your post"
  defp action_text("event_created"), do: "added a new event"
  defp action_text("rsvp_changed"), do: "updated their RSVP"
  defp action_text("member_joined"), do: "joined the family"
  defp action_text(kind), do: kind
end
