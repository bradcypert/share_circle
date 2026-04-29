defmodule ShareCircle.Notifications do
  @moduledoc """
  In-app notifications, notification preferences, and push subscriptions.

  Notifications are created by domain event handlers (Posts, Chat, Calendar).
  They are delivered in-app (stored + real-time PubSub), optionally by email,
  and optionally by web push — based on the recipient's preferences.
  """

  import Ecto.Query

  alias ShareCircle.Accounts.Scope
  alias ShareCircle.Notifications.{Notification, NotificationPreference, PushSubscription}
  alias ShareCircle.PubSub
  alias ShareCircle.Repo

  # ---------------------------------------------------------------------------
  # Notifications
  # ---------------------------------------------------------------------------

  @doc """
  Creates a notification and delivers it according to the recipient's preferences.
  Called by domain contexts after a state mutation.

  Required attrs: :family_id, :recipient_user_id, :kind
  Optional attrs: :actor_user_id, :subject_type, :subject_id, :payload
  """
  def notify(attrs) when is_map(attrs) do
    changeset = Notification.create_changeset(attrs)

    with {:ok, notification} <- Repo.insert(changeset) do
      notification = Repo.preload(notification, [:actor_user])

      # Real-time: push to user channel
      PubSub.broadcast(
        PubSub.user_topic(notification.recipient_user_id),
        :notification_created,
        %{notification: notification}
      )

      # Async delivery (email/push) via Oban
      %{notification_id: notification.id}
      |> ShareCircleWorkers.DeliverNotification.new()
      |> Oban.insert()

      {:ok, notification}
    end
  end

  @doc "Lists the current user's notifications, newest first."
  def list_notifications(%Scope{user: user}, opts \\ []) do
    limit = Keyword.get(opts, :limit, 30)
    unread_only = Keyword.get(opts, :unread_only, false)

    query =
      from n in Notification,
        where: n.recipient_user_id == ^user.id,
        order_by: [desc: n.inserted_at],
        limit: ^limit,
        preload: [:actor_user]

    query =
      if unread_only do
        where(query, [n], is_nil(n.read_at))
      else
        query
      end

    Repo.all(query)
  end

  @doc "Returns count of unread notifications for the user."
  def unread_count(%Scope{user: user}) do
    Repo.aggregate(
      from(n in Notification,
        where: n.recipient_user_id == ^user.id and is_nil(n.read_at)
      ),
      :count
    )
  end

  @doc "Marks a single notification as read."
  def mark_read(%Scope{user: user}, notification_id) do
    now = DateTime.utc_now()

    case Repo.get_by(Notification, id: notification_id, recipient_user_id: user.id) do
      nil ->
        {:error, :not_found}

      notification ->
        {:ok, updated} = Repo.update(Ecto.Changeset.change(notification, read_at: now))

        PubSub.broadcast(PubSub.user_topic(user.id), :notification_read, %{
          notification_id: updated.id
        })

        {:ok, updated}
    end
  end

  @doc "Marks all of the current user's notifications as read."
  def mark_all_read(%Scope{user: user}) do
    now = DateTime.utc_now()

    {count, _} =
      Repo.update_all(
        from(n in Notification,
          where: n.recipient_user_id == ^user.id and is_nil(n.read_at)
        ),
        set: [read_at: now]
      )

    PubSub.broadcast(PubSub.user_topic(user.id), :notifications_all_read, %{})
    {:ok, count}
  end

  # ---------------------------------------------------------------------------
  # Preferences
  # ---------------------------------------------------------------------------

  @doc "Gets all notification preferences for the current user (global + family-specific)."
  def list_preferences(%Scope{user: user, family: family}) do
    Repo.all(
      from p in NotificationPreference,
        where: p.user_id == ^user.id and (is_nil(p.family_id) or p.family_id == ^family.id)
    )
  end

  @doc "Upserts a notification preference for the given kind."
  def update_preference(%Scope{user: user, family: family}, kind, channels) do
    existing =
      Repo.get_by(NotificationPreference,
        user_id: user.id,
        family_id: family.id,
        kind: kind
      )

    changeset =
      NotificationPreference.changeset(
        existing || %NotificationPreference{},
        %{user_id: user.id, family_id: family.id, kind: kind, channels: channels}
      )

    Repo.insert_or_update(changeset)
  end

  @doc "Returns the effective channels map for a given user/family/kind."
  def get_channels(user_id, family_id, kind) do
    family_pref =
      Repo.get_by(NotificationPreference, user_id: user_id, family_id: family_id, kind: kind)

    global_pref =
      from(p in NotificationPreference,
        where: p.user_id == ^user_id and is_nil(p.family_id) and p.kind == ^kind
      )
      |> Repo.one()

    case family_pref || global_pref do
      nil -> %{"in_app" => true, "email" => false, "push" => true}
      pref -> pref.channels
    end
  end

  # ---------------------------------------------------------------------------
  # Push subscriptions
  # ---------------------------------------------------------------------------

  @doc "Registers a web push subscription for the current user."
  def register_push_subscription(%Scope{user: user}, attrs) do
    changeset =
      PushSubscription.changeset(%PushSubscription{}, Map.put(attrs, "user_id", user.id))

    case Repo.insert(changeset,
           on_conflict: {:replace, [:p256dh_key, :auth_key, :user_agent, :last_used_at]},
           conflict_target: [:user_id, :endpoint]
         ) do
      {:ok, sub} -> {:ok, sub}
      {:error, cs} -> {:error, cs}
    end
  end

  @doc "Removes a push subscription by id."
  def delete_push_subscription(%Scope{user: user}, id) do
    case Repo.get_by(PushSubscription, id: id, user_id: user.id) do
      nil -> {:error, :not_found}
      sub -> Repo.delete(sub)
    end
  end

  @doc "Lists active push subscriptions for a user_id (used by delivery worker)."
  def list_push_subscriptions(user_id) do
    Repo.all(from s in PushSubscription, where: s.user_id == ^user_id)
  end
end
