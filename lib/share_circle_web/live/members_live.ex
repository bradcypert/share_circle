defmodule ShareCircleWeb.MembersLive do
  use ShareCircleWeb, :live_view

  alias ShareCircle.Accounts.UserNotifier
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
        invitations = Families.list_invitations(scope)
        can_invite = membership.role in ~w(owner admin)

        {:ok,
         socket
         |> assign(:current_scope, scope)
         |> assign(:family_id, family_id)
         |> assign(:members, members)
         |> assign(:invitations, invitations)
         |> assign(:can_invite, can_invite)
         |> assign(:show_invite_form, false)
         |> assign(:invite_email, "")
         |> assign(:invite_role, "member")
         |> assign(:invite_error, nil)}
    end
  end

  @impl true
  def handle_event("toggle_invite_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_invite_form, !socket.assigns.show_invite_form)
     |> assign(:invite_email, "")
     |> assign(:invite_role, "member")
     |> assign(:invite_error, nil)}
  end

  def handle_event("update_invite_email", %{"value" => email}, socket) do
    {:noreply, assign(socket, :invite_email, email)}
  end

  def handle_event("update_invite_role", %{"value" => role}, socket) do
    {:noreply, assign(socket, :invite_role, role)}
  end

  def handle_event("send_invitation", _params, socket) do
    scope = socket.assigns.current_scope
    email = String.trim(socket.assigns.invite_email)
    role = socket.assigns.invite_role

    case Families.invite_member(scope, %{"email" => email, "role" => role}) do
      {:ok, {_invitation, url_token}} ->
        accept_url =
          ShareCircleWeb.Endpoint.url() <>
            ~p"/invitations/#{url_token}/accept"

        UserNotifier.deliver_invitation_instructions(
          email,
          scope.family.name,
          accept_url
        )

        invitations = Families.list_invitations(scope)

        {:noreply,
         socket
         |> assign(:invitations, invitations)
         |> assign(:show_invite_form, false)
         |> assign(:invite_email, "")
         |> assign(:invite_error, nil)}

      {:error, %Ecto.Changeset{} = cs} ->
        msg =
          cs.errors
          |> Enum.map(fn {field, {msg, _}} -> "#{field} #{msg}" end)
          |> Enum.join(", ")

        {:noreply, assign(socket, :invite_error, msg)}

      {:error, :unauthorized} ->
        {:noreply, assign(socket, :invite_error, "You don't have permission to invite members.")}

      {:error, _} ->
        {:noreply, assign(socket, :invite_error, "Something went wrong. Please try again.")}
    end
  end

  def handle_event("revoke_invitation", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    case Families.revoke_invitation(scope, id) do
      {:ok, _} ->
        invitations = Families.list_invitations(scope)
        {:noreply, assign(socket, :invitations, invitations)}

      {:error, _} ->
        {:noreply, socket}
    end
  end
end
