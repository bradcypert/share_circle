defmodule ShareCircleWeb.ChatLive do
  use ShareCircleWeb, :live_view

  alias ShareCircle.Chat
  alias ShareCircle.Families
  alias ShareCircle.PubSub
  alias ShareCircleWeb.LiveHelpers

  @impl true
  def mount(%{"family_id" => family_id} = params, _session, socket) do
    user = socket.assigns.current_scope.user

    case ShareCircle.Families.get_membership_for_user(family_id, user.id) do
      nil -> {:ok, push_navigate(socket, to: ~p"/families")}
      %{family: family} = membership -> do_mount(socket, params, family_id, family, membership)
    end
  end

  defp do_mount(socket, params, family_id, family, membership) do
    scope = %{socket.assigns.current_scope | family: family, membership: membership}
    conversations = Chat.list_conversations(scope)

    {active_conv, messages, msg_pagination} = initial_conversation(scope, conversations, params)

    if active_conv, do: PubSub.subscribe(PubSub.conversation_topic(active_conv.id))

    family_members =
      scope
      |> Families.list_members()
      |> Enum.reject(&(&1.user_id == socket.assigns.current_scope.user.id))

    avatar_urls = LiveHelpers.build_avatar_urls(scope, [scope.user | Enum.map(messages, & &1.author)])

    {:ok,
     socket
     |> assign(:current_scope, scope)
     |> assign(:family_id, family_id)
     |> assign(:conversations, conversations)
     |> assign(:active_conv, active_conv)
     |> assign(:messages, messages)
     |> assign(:message_pagination, msg_pagination)
     |> assign(:message_form, to_form(%{"body" => ""}, as: "message"))
     |> assign(:typing_users, [])
     |> assign(:family_members, family_members)
     |> assign(:new_conv_open, false)
     |> assign(:new_conv_kind, "direct")
     |> assign(:new_conv_name, "")
     |> assign(:new_conv_member_ids, [])
     |> assign(:editing_message_id, nil)
     |> assign(:editing_message_body, "")
     |> assign(:show_sidebar, false)
     |> assign(:typing_timer, nil)
     |> assign(:avatar_urls, avatar_urls)}
  end

  defp initial_conversation(scope, _conversations, %{"conversation_id" => id}),
    do: load_conversation(scope, id)

  defp initial_conversation(scope, [first | _], _params), do: load_conversation(scope, first.id)
  defp initial_conversation(_scope, [], _params), do: {nil, [], %{next_cursor: nil}}

  @impl true
  def handle_params(%{"conversation_id" => conv_id}, _uri, socket) do
    scope = socket.assigns.current_scope

    if socket.assigns.active_conv && socket.assigns.active_conv.id == conv_id do
      {:noreply, socket}
    else
      # Unsubscribe from old, subscribe to new
      if socket.assigns.active_conv do
        PubSub.unsubscribe(PubSub.conversation_topic(socket.assigns.active_conv.id))
      end

      {conv, messages, msg_pagination} = load_conversation(scope, conv_id)

      if conv do
        PubSub.subscribe(PubSub.conversation_topic(conv.id))
      end

      new_avatar_urls = LiveHelpers.build_avatar_urls(scope, Enum.map(messages, & &1.author))

      {:noreply,
       socket
       |> assign(:active_conv, conv)
       |> assign(:messages, messages)
       |> assign(:message_pagination, msg_pagination)
       |> update(:avatar_urls, &Map.merge(&1, new_avatar_urls))
       |> assign(:typing_users, [])}
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("toggle_sidebar", _params, socket) do
    {:noreply, assign(socket, :show_sidebar, !socket.assigns.show_sidebar)}
  end

  def handle_event("toggle_new_conv", _params, socket) do
    {:noreply,
     socket
     |> assign(:new_conv_open, !socket.assigns.new_conv_open)
     |> assign(:new_conv_kind, "direct")
     |> assign(:new_conv_name, "")
     |> assign(:new_conv_member_ids, [])}
  end

  def handle_event("set_new_conv_kind", %{"kind" => kind}, socket) do
    {:noreply, assign(socket, new_conv_kind: kind, new_conv_member_ids: [])}
  end

  def handle_event("update_new_conv_name", %{"value" => name}, socket) do
    {:noreply, assign(socket, :new_conv_name, name)}
  end

  def handle_event("toggle_new_conv_member", %{"id" => id}, socket) do
    current = socket.assigns.new_conv_member_ids

    updated =
      if socket.assigns.new_conv_kind == "direct" do
        if current == [id], do: [], else: [id]
      else
        if id in current, do: List.delete(current, id), else: [id | current]
      end

    {:noreply, assign(socket, :new_conv_member_ids, updated)}
  end

  def handle_event("create_conversation", _params, socket) do
    scope = socket.assigns.current_scope
    kind = socket.assigns.new_conv_kind
    member_ids = socket.assigns.new_conv_member_ids

    attrs =
      case kind do
        "direct" ->
          %{"kind" => "direct", "member_user_ids" => member_ids}

        "group" ->
          %{
            "kind" => "group",
            "name" => socket.assigns.new_conv_name,
            "member_user_ids" => member_ids
          }
      end

    case Chat.create_conversation(scope, attrs) do
      {:ok, conv} ->
        conversations = Chat.list_conversations(scope)

        {:noreply,
         socket
         |> assign(:conversations, conversations)
         |> assign(:new_conv_open, false)
         |> assign(:new_conv_member_ids, [])
         |> assign(:new_conv_name, "")
         |> push_patch(to: ~p"/families/#{socket.assigns.family_id}/chat/#{conv.id}")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not create conversation.")}
    end
  end

  def handle_event("edit_message", %{"id" => id}, socket) do
    msg = Enum.find(socket.assigns.messages, &(&1.id == id))

    {:noreply,
     socket
     |> assign(:editing_message_id, id)
     |> assign(:editing_message_body, (msg && msg.body) || "")}
  end

  def handle_event("cancel_edit_message", _params, socket) do
    {:noreply, socket |> assign(:editing_message_id, nil) |> assign(:editing_message_body, "")}
  end

  def handle_event("update_editing_message_body", %{"value" => value}, socket) do
    {:noreply, assign(socket, :editing_message_body, value)}
  end

  def handle_event("save_message", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    case Chat.update_message(scope, id, %{"body" => socket.assigns.editing_message_body}) do
      {:ok, _msg} ->
        {:noreply,
         socket |> assign(:editing_message_id, nil) |> assign(:editing_message_body, "")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not save message.")}
    end
  end

  def handle_event("delete_message", %{"id" => id}, socket) do
    Chat.delete_message(socket.assigns.current_scope, id)
    {:noreply, socket}
  end

  def handle_event("send_message", %{"message" => %{"body" => body}}, socket) do
    scope = socket.assigns.current_scope
    conv = socket.assigns.active_conv

    # Cancel any pending stop-typing timer and broadcast stopped immediately
    if socket.assigns.typing_timer, do: Process.cancel_timer(socket.assigns.typing_timer)
    if conv, do: Chat.broadcast_typing_stopped(scope, conv.id)

    case Chat.send_message(scope, conv.id, %{"body" => body}) do
      {:ok, _message} ->
        {:noreply,
         socket
         |> assign(:message_form, to_form(%{"body" => ""}, as: "message"))
         |> assign(:typing_timer, nil)
         |> push_event("clear-message-input", %{})}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not send message.")}
    end
  end

  def handle_event("update_message", %{"message" => %{"body" => body}}, socket) do
    {:noreply, assign(socket, :message_form, to_form(%{"body" => body}, as: "message"))}
  end

  def handle_event("typing", _params, socket) do
    scope = socket.assigns.current_scope
    conv = socket.assigns.active_conv

    if conv do
      Chat.broadcast_typing(scope, conv.id)

      # Cancel the previous debounce timer and start a new one
      if socket.assigns.typing_timer, do: Process.cancel_timer(socket.assigns.typing_timer)
      timer = Process.send_after(self(), :stop_typing, 3_000)

      {:noreply, assign(socket, :typing_timer, timer)}
    else
      {:noreply, socket}
    end
  end

  def handle_event(
        "load_older",
        _,
        %{assigns: %{message_pagination: %{next_cursor: nil}}} = socket
      ),
      do: {:noreply, socket}

  def handle_event("load_older", _params, socket) do
    scope = socket.assigns.current_scope
    conv = socket.assigns.active_conv
    cursor = socket.assigns.message_pagination.next_cursor

    {:ok, {older_messages, pagination}} =
      Chat.list_messages(scope, conv.id, cursor: cursor)

    new_avatar_urls = LiveHelpers.build_avatar_urls(scope, Enum.map(older_messages, & &1.author))

    {:noreply,
     socket
     |> update(:messages, &(Enum.reverse(older_messages) ++ &1))
     |> assign(:message_pagination, pagination)
     |> update(:avatar_urls, &Map.merge(&1, new_avatar_urls))}
  end

  def handle_event("select_conversation", %{"id" => conv_id}, socket) do
    {:noreply,
     socket
     |> assign(:show_sidebar, false)
     |> push_patch(to: ~p"/families/#{socket.assigns.family_id}/chat/#{conv_id}")}
  end

  @impl true
  def handle_info({:message_created, %{message: message}}, socket) do
    new_avatar_urls = LiveHelpers.build_avatar_urls(socket.assigns.current_scope, [message.author])

    {:noreply,
     socket
     |> update(:messages, &(&1 ++ [message]))
     |> update(:avatar_urls, &Map.merge(&1, new_avatar_urls))}
  end

  def handle_info({:message_updated, %{message: message}}, socket) do
    messages =
      Enum.map(socket.assigns.messages, fn m ->
        if m.id == message.id, do: message, else: m
      end)

    {:noreply, assign(socket, :messages, messages)}
  end

  def handle_info({:message_deleted, %{message_id: id}}, socket) do
    messages = Enum.reject(socket.assigns.messages, &(&1.id == id))
    {:noreply, assign(socket, :messages, messages)}
  end

  def handle_info({:typing_started, %{user_id: user_id}}, socket) do
    if user_id == socket.assigns.current_scope.user.id do
      {:noreply, socket}
    else
      typing = Enum.uniq([user_id | socket.assigns.typing_users])
      {:noreply, assign(socket, :typing_users, typing)}
    end
  end

  def handle_info({:typing_stopped, %{user_id: user_id}}, socket) do
    typing = Enum.reject(socket.assigns.typing_users, &(&1 == user_id))
    {:noreply, assign(socket, :typing_users, typing)}
  end

  def handle_info(:stop_typing, socket) do
    scope = socket.assigns.current_scope
    conv = socket.assigns.active_conv
    if conv, do: Chat.broadcast_typing_stopped(scope, conv.id)
    {:noreply, assign(socket, :typing_timer, nil)}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  defp typing_label([], _members), do: nil

  defp typing_label(user_ids, members) do
    names =
      user_ids
      |> Enum.map(fn uid ->
        case Enum.find(members, &(&1.user_id == uid)) do
          %{user: %{display_name: name}} -> name
          _ -> "Someone"
        end
      end)

    case names do
      [name] -> "#{name} is typing…"
      [a, b] -> "#{a} and #{b} are typing…"
      [a | _] -> "#{a} and others are typing…"
    end
  end

  defp conversation_display_name(%{kind: "family"}), do: "Family Chat"
  defp conversation_display_name(%{kind: "group", name: name}), do: name

  defp conversation_display_name(%{kind: "direct", members: members}) do
    Enum.map_join(members, ", ", & &1.user.display_name)
  end

  defp load_conversation(scope, conv_id) do
    case Chat.get_conversation(scope, conv_id) do
      {:ok, conv} ->
        {:ok, {messages, pagination}} = Chat.list_messages(scope, conv.id)
        # Messages come back newest-first; reverse for display
        {conv, Enum.reverse(messages), pagination}

      {:error, _} ->
        {nil, [], %{next_cursor: nil}}
    end
  end
end
