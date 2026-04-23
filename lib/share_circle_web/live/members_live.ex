defmodule ShareCircleWeb.MembersLive do
  use ShareCircleWeb, :live_view

  alias ShareCircle.Families

  @impl true
  def mount(%{"family_id" => family_id}, _session, socket) do
    user = socket.assigns.current_scope.user

    case Families.get_membership_for_user(family_id, user.id) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/families")}

      %{family: family} = membership ->
        scope = %{socket.assigns.current_scope | family: family, membership: membership}
        members = Families.list_members(scope)

        {:ok,
         socket
         |> assign(:current_scope, scope)
         |> assign(:family_id, family_id)
         |> assign(:members, members)}
    end
  end
end
