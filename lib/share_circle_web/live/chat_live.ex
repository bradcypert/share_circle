defmodule ShareCircleWeb.ChatLive do
  use ShareCircleWeb, :live_view

  alias ShareCircle.Chat
  alias ShareCircle.Families
  alias ShareCircle.PubSub

  @impl true
  def mount(%{"family_id" => family_id} = params, _session, socket) do
    user = socket.assigns.current_scope.user

    case ShareCircle.Families.get_membership_for_user(family_id, user.id) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/families")}

      %{family: family} = membership ->
        scope = %{socket.assigns.current_scope | family: family, membership: membership}
        conversations = Chat.list_conversations(scope)

        conversation_id = params["conversation_id"]

        {active_conv, messages} =
          case conversation_id do
            nil ->
              case conversations do
                [first | _] -> load_conversation(scope, first.id)
                [] -> {nil, []}
              end

            id ->
              load_conversation(scope, id)
          end

        if active_conv do
          PubSub.subscribe(PubSub.conversation_topic(active_conv.id))
        end

        family_members =
          scope
          |> Families.list_members()
          |> Enum.reject(&(&1.user_id == user.id))

        {:ok,
         socket
         |> assign(:current_scope, scope)
         |> assign(:family_id, family_id)
         |> assign(:conversations, conversations)
         |> assign(:active_conv, active_conv)
         |> assign(:messages, messages)
         |> assign(:message_form, to_form(%{"body" => ""}, as: "message"))
         |> assign(:typing_users, [])
         |> assign(:family_members, family_members)
         |> assign(:new_conv_open, false)
         |> assign(:new_conv_kind, "direct")
         |> assign(:new_conv_name, "")
         |> assign(:new_conv_member_ids, [])}
    end
  end

  @impl true
  def handle_params(%{"conversation_id" => conv_id}, _uri, socket) do
    scope = socket.assigns.current_scope

    if socket.assigns.active_conv && socket.assigns.active_conv.id == conv_id do
      {:noreply, socket}
    else
      # Unsubscribe from old, subscribe to new
      if socket.assigns.active_conv do
        PubSub.subscribe(PubSub.conversation_topic(socket.assigns.active_conv.id))
      end

      {conv, messages} = load_conversation(scope, conv_id)

      if conv do
        PubSub.subscribe(PubSub.conversation_topic(conv.id))
      end

      {:noreply,
       socket
       |> assign(:active_conv, conv)
       |> assign(:messages, messages)
       |> assign(:typing_users, [])}
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
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
        "direct" -> %{"kind" => "direct", "member_user_ids" => member_ids}
        "group" -> %{"kind" => "group", "name" => socket.assigns.new_conv_name, "member_user_ids" => member_ids}
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
        {:noreply, socket}
    end
  end

  def handle_event("send_message", %{"message" => %{"body" => body}}, socket) do
    scope = socket.assigns.current_scope
    conv = socket.assigns.active_conv

    case Chat.send_message(scope, conv.id, %{"body" => body}) do
      {:ok, _message} ->
        {:noreply, assign(socket, :message_form, to_form(%{"body" => ""}, as: "message"))}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("select_conversation", %{"id" => conv_id}, socket) do
    {:noreply,
     push_patch(socket, to: ~p"/families/#{socket.assigns.family_id}/chat/#{conv_id}")}
  end

  @impl true
  def handle_info({:message_created, %{message: message}}, socket) do
    {:noreply, update(socket, :messages, &[message | &1])}
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
    typing = Enum.uniq([user_id | socket.assigns.typing_users])
    {:noreply, assign(socket, :typing_users, typing)}
  end

  def handle_info({:typing_stopped, %{user_id: user_id}}, socket) do
    typing = Enum.reject(socket.assigns.typing_users, &(&1 == user_id))
    {:noreply, assign(socket, :typing_users, typing)}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  defp conversation_display_name(%{kind: "family"}), do: "Family Chat"
  defp conversation_display_name(%{kind: "group", name: name}), do: name
  defp conversation_display_name(%{kind: "direct", members: members}) do
    members
    |> Enum.map(& &1.user.display_name)
    |> Enum.join(", ")
  end

  defp load_conversation(scope, conv_id) do
    case Chat.get_conversation(scope, conv_id) do
      {:ok, conv} ->
        {:ok, {messages, _pagination}} = Chat.list_messages(scope, conv.id)
        # Messages come back newest-first; reverse for display
        {conv, Enum.reverse(messages)}

      {:error, _} ->
        {nil, []}
    end
  end
end
