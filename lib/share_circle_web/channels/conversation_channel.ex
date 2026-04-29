defmodule ShareCircleWeb.ConversationChannel do
  @moduledoc false
  use Phoenix.Channel

  import Ecto.Query

  alias ShareCircle.Chat.ConversationMember
  alias ShareCircle.PubSub
  alias ShareCircle.Repo

  @impl true
  def join("conversation:" <> conversation_id, _params, socket) do
    user = socket.assigns.current_user

    member =
      from(cm in ConversationMember,
        where:
          cm.conversation_id == ^conversation_id and cm.user_id == ^user.id and
            is_nil(cm.left_at)
      )
      |> Repo.one()

    if member do
      PubSub.subscribe(PubSub.conversation_topic(conversation_id))
      {:ok, assign(socket, :conversation_id, conversation_id)}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  # Typing indicators — broadcast to other members, don't persist
  @impl true
  def handle_in("typing.start", _params, socket) do
    broadcast_from!(socket, "typing.started", %{user_id: socket.assigns.current_user.id})
    {:noreply, socket}
  end

  def handle_in("typing.stop", _params, socket) do
    broadcast_from!(socket, "typing.stopped", %{user_id: socket.assigns.current_user.id})
    {:noreply, socket}
  end

  # PubSub events from the Chat context → push to client
  @impl true
  def handle_info({event, payload}, socket) when is_atom(event) do
    push(socket, Atom.to_string(event), payload)
    {:noreply, socket}
  end
end
