defmodule ShareCircle.Chat do
  @moduledoc """
  Conversations and messages.

  Conversations are family-scoped. The `kind` determines who can join:
  - "family" — one per family, all members auto-joined
  - "group"  — created explicitly, members specified at creation
  - "direct" — between exactly two users

  All mutations verify membership via ConversationMember before proceeding.
  """

  import Ecto.Query

  alias ShareCircle.Accounts.Scope
  alias ShareCircle.Chat.{Conversation, ConversationMember, Message}
  alias ShareCircle.Events
  alias ShareCircle.Families
  alias ShareCircle.Families.Policy
  alias ShareCircle.Notifications
  alias ShareCircle.Repo

  # ---------------------------------------------------------------------------
  # Conversations
  # ---------------------------------------------------------------------------

  @doc """
  Creates or returns the family-wide conversation for the given family.
  Adds all current members if creating fresh.
  """
  def ensure_family_conversation(family_id) do
    case Repo.get_by(Conversation, family_id: family_id, kind: "family") do
      %Conversation{} = conv ->
        {:ok, conv}

      nil ->
        Repo.transaction(fn ->
          conv =
            Repo.insert!(
              Conversation.create_changeset(%{family_id: family_id, kind: "family"})
            )

          # Add all existing members
          memberships = Families.list_memberships_for_family(family_id)

          Enum.each(memberships, fn m ->
            add_member_to_conversation(conv.id, m.user_id, family_id)
          end)

          conv
        end)
    end
  end

  @doc "Lists conversations the current user is in, for a given family."
  def list_conversations(%Scope{user: user, family: family}) do
    from(c in Conversation,
      join: cm in ConversationMember,
      on: cm.conversation_id == c.id and cm.user_id == ^user.id and is_nil(cm.left_at),
      where: c.family_id == ^family.id and is_nil(c.deleted_at),
      order_by: [desc_nulls_last: c.last_message_at],
      preload: [members: :user]
    )
    |> Repo.all()
  end

  @doc "Returns a single conversation if the user is a member."
  def get_conversation(%Scope{user: user, family: family}, conversation_id) do
    conv =
      from(c in Conversation,
        join: cm in ConversationMember,
        on: cm.conversation_id == c.id and cm.user_id == ^user.id and is_nil(cm.left_at),
        where:
          c.id == ^conversation_id and c.family_id == ^family.id and is_nil(c.deleted_at),
        preload: [members: :user]
      )
      |> Repo.one()

    if conv, do: {:ok, conv}, else: {:error, :not_found}
  end

  @doc "Creates a group or direct conversation. Scope must have family + membership."
  def create_conversation(%Scope{user: user, family: family, membership: membership}, attrs) do
    with :ok <- Policy.authorize(membership, :create_conversation) do
      member_user_ids = Map.get(attrs, "member_user_ids", [])

      Repo.transaction(fn ->
        conv =
          Repo.insert!(
            Conversation.create_changeset(%{
              family_id: family.id,
              kind: attrs["kind"],
              name: attrs["name"],
              created_by_user_id: user.id
            })
          )

        # Always add creator
        all_user_ids = Enum.uniq([user.id | member_user_ids])

        Enum.each(all_user_ids, fn uid ->
          add_member_to_conversation(conv.id, uid, family.id)
        end)

        Repo.preload(conv, members: :user)
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # Messages
  # ---------------------------------------------------------------------------

  @doc """
  Returns paginated messages for a conversation (newest first).
  Options: `limit` (default 50, max 100), `cursor`.
  """
  def list_messages(%Scope{} = scope, conversation_id, opts \\ []) do
    with {:ok, _conv} <- get_conversation(scope, conversation_id) do
      limit = min(Keyword.get(opts, :limit, 50), 100)
      cursor = Keyword.get(opts, :cursor)

      query =
        from m in Message,
          where: m.conversation_id == ^conversation_id and is_nil(m.deleted_at),
          order_by: [desc: m.inserted_at, desc: m.id],
          limit: ^(limit + 1),
          preload: [:author]

      messages = query |> apply_cursor(cursor) |> Repo.all()
      {items, has_more} = split_page(messages, limit)
      {:ok, {items, build_pagination(items, has_more)}}
    end
  end

  @doc "Sends a message. Scope must have family and membership."
  def send_message(
        %Scope{user: user, family: family, membership: membership},
        conversation_id,
        attrs
      ) do
    with :ok <- Policy.authorize(membership, :send_message),
         {:ok, conv} <- get_conversation(%Scope{user: user, family: family}, conversation_id) do
      msg_attrs = %{
        conversation_id: conv.id,
        family_id: family.id,
        author_id: user.id,
        body: attrs["body"],
        reply_to_message_id: attrs["reply_to_message_id"]
      }

      with {:ok, message} <-
             Repo.insert(Message.create_changeset(msg_attrs)) do
        message = Repo.preload(message, :author)
        update_conversation_preview(conv.id, message)
        Events.broadcast_to_conversation(conv.id, :message_created, %{message: message})
        notify_conversation_members(conv, user.id, family.id, message)
        {:ok, message}
      end
    end
  end

  @doc "Edits a message. Only the author may edit."
  def update_message(%Scope{user: user}, message_id, attrs) do
    with {:ok, message} <- get_editable_message(message_id, user.id) do
      message
      |> Message.update_changeset(attrs)
      |> Repo.update()
      |> tap_ok(fn updated ->
        updated = Repo.preload(updated, :author)
        Events.broadcast_to_conversation(message.conversation_id, :message_updated, %{
          message: updated
        })
      end)
    end
  end

  @doc "Soft-deletes a message. Author or family admin/owner may delete."
  def delete_message(%Scope{user: user, family: family}, message_id) do
    with {:ok, message} <- load_message_with_membership(message_id, user.id, family) do
      message
      |> Ecto.Changeset.change(deleted_at: DateTime.utc_now())
      |> Repo.update()
      |> tap_ok(fn _ ->
        Events.broadcast_to_conversation(message.conversation_id, :message_deleted, %{
          message_id: message.id
        })
      end)
    end
  end

  @doc "Updates the caller's last_read_message_id for the conversation."
  def mark_read(%Scope{user: user, family: family}, conversation_id, message_id) do
    case Repo.get_by(ConversationMember,
           conversation_id: conversation_id,
           user_id: user.id,
           left_at: nil
         ) do
      nil ->
        {:error, :not_found}

      member ->
        with {:ok, updated} <-
               member
               |> ConversationMember.mark_read_changeset(message_id)
               |> Repo.update() do
          Events.broadcast_to_conversation(conversation_id, :read_receipt_updated, %{
            user_id: user.id,
            family_id: family.id,
            last_read_message_id: message_id
          })

          {:ok, updated}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Internal helpers used by Families context
  # ---------------------------------------------------------------------------

  @doc false
  def add_member_to_conversation(conversation_id, user_id, family_id) do
    Repo.insert!(
      ConversationMember.create_changeset(%{
        conversation_id: conversation_id,
        user_id: user_id,
        family_id: family_id,
        joined_at: DateTime.utc_now()
      }),
      on_conflict: :nothing,
      conflict_target: [:conversation_id, :user_id]
    )
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp get_editable_message(message_id, user_id) do
    case Repo.get_by(Message, id: message_id, author_id: user_id, deleted_at: nil) do
      nil -> {:error, :not_found}
      message -> {:ok, message}
    end
  end

  defp load_message_with_membership(message_id, user_id, family) do
    case Repo.get_by(Message, id: message_id, family_id: family.id, deleted_at: nil) do
      nil ->
        {:error, :not_found}

      message ->
        membership = Families.get_membership_for_user(family.id, user_id)

        cond do
          is_nil(membership) -> {:error, :not_found}
          message.author_id == user_id -> {:ok, message}
          membership.role in ~w(owner admin) -> {:ok, message}
          true -> {:error, :unauthorized}
        end
    end
  end

  defp update_conversation_preview(conversation_id, message) do
    preview = if message.body, do: String.slice(message.body, 0, 100), else: "(media)"

    from(c in Conversation, where: c.id == ^conversation_id)
    |> Repo.update_all(set: [last_message_at: message.inserted_at, last_message_preview: preview])
  end

  defp tap_ok({:ok, result}, fun) do
    fun.(result)
    {:ok, result}
  end

  defp tap_ok(error, _fun), do: error

  # Cursor pagination --------------------------------------------------------

  defp apply_cursor(query, nil), do: query

  defp apply_cursor(query, cursor) do
    case decode_cursor(cursor) do
      {:ok, {ts, id}} ->
        from m in query,
          where: m.inserted_at < ^ts or (m.inserted_at == ^ts and m.id < ^id)

      :error ->
        query
    end
  end

  defp decode_cursor(cursor) do
    try do
      {ts, id} = cursor |> Base.decode64!() |> :erlang.binary_to_term([:safe])
      {:ok, {ts, id}}
    rescue
      _ -> :error
    end
  end

  defp split_page(items, limit) when length(items) > limit do
    {Enum.take(items, limit), true}
  end

  defp split_page(items, _limit), do: {items, false}

  defp build_pagination([], _has_more), do: %{next_cursor: nil}

  defp build_pagination(items, true) do
    last = List.last(items)
    cursor = :erlang.term_to_binary({last.inserted_at, last.id}) |> Base.encode64()
    %{next_cursor: cursor}
  end

  defp build_pagination(_items, false), do: %{next_cursor: nil}

  defp notify_conversation_members(conv, actor_user_id, family_id, message) do
    from(cm in ConversationMember,
      where: cm.conversation_id == ^conv.id and is_nil(cm.left_at) and cm.user_id != ^actor_user_id
    )
    |> ShareCircle.Repo.all()
    |> Enum.each(fn cm ->
      Notifications.notify(%{
        family_id: family_id,
        recipient_user_id: cm.user_id,
        actor_user_id: actor_user_id,
        kind: "new_message",
        subject_type: "Message",
        subject_id: message.id,
        payload: %{preview: String.slice(message.body, 0, 100)}
      })
    end)
  end
end
