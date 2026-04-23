defmodule ShareCircleWeb.UserChannel do
  use Phoenix.Channel

  alias ShareCircle.PubSub

  @impl true
  def join("user:" <> user_id, _params, socket) do
    if socket.assigns.current_user.id == user_id do
      PubSub.subscribe(PubSub.user_topic(user_id))
      {:ok, assign(socket, :user_id, user_id)}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_info({event, payload}, socket) when is_atom(event) do
    push(socket, Atom.to_string(event), payload)
    {:noreply, socket}
  end
end
