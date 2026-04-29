defmodule ShareCircleWeb.FamilyChannel do
  @moduledoc false
  use Phoenix.Channel

  alias ShareCircle.Families
  alias ShareCircle.PubSub

  @impl true
  def join("family:" <> family_id, _params, socket) do
    user = socket.assigns.current_user

    case Families.get_membership_for_user(family_id, user.id) do
      nil ->
        {:error, %{reason: "unauthorized"}}

      membership ->
        PubSub.subscribe(PubSub.family_topic(family_id))
        {:ok, assign(socket, :family_id, family_id) |> assign(:membership, membership)}
    end
  end

  @impl true
  def handle_info({event, payload}, socket) when is_atom(event) do
    push(socket, to_string(event), payload)
    {:noreply, socket}
  end
end
