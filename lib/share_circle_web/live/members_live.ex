defmodule ShareCircleWeb.MembersLive do
  use ShareCircleWeb, :live_view

  alias ShareCircle.Accounts
  alias ShareCircle.Accounts.UserNotifier
  alias ShareCircle.Families
  alias ShareCircleWeb.LiveHelpers

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
         |> assign(:invite_error, nil)
         |> assign(:show_add_child_form, false)
         |> assign(:child_email, "")
         |> assign(:child_name, "")
         |> assign(:child_error, nil)
         |> assign(:promote_target, nil)
         |> assign(:current_avatar_url, LiveHelpers.get_user_avatar_url(scope, scope.user))}
    end
  end

  # ---------------------------------------------------------------------------
  # Invite member handlers
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("toggle_invite_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_invite_form, !socket.assigns.show_invite_form)
     |> assign(:show_add_child_form, false)
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
          Enum.map_join(cs.errors, ", ", fn {field, {msg, _}} -> "#{field} #{msg}" end)

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

  # ---------------------------------------------------------------------------
  # Add child account handlers
  # ---------------------------------------------------------------------------

  def handle_event("toggle_add_child_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_add_child_form, !socket.assigns.show_add_child_form)
     |> assign(:show_invite_form, false)
     |> assign(:child_email, "")
     |> assign(:child_name, "")
     |> assign(:child_error, nil)}
  end

  def handle_event("update_child_email", %{"value" => email}, socket) do
    {:noreply, assign(socket, :child_email, email)}
  end

  def handle_event("update_child_name", %{"value" => name}, socket) do
    {:noreply, assign(socket, :child_name, name)}
  end

  def handle_event("add_child_account", _params, socket) do
    scope = socket.assigns.current_scope
    guardian = scope.user
    email = String.trim(socket.assigns.child_email)
    name = String.trim(socket.assigns.child_name)

    with {:ok, child} <- Accounts.create_child_account(guardian, %{"email" => email, "display_name" => name}),
         {:ok, _membership} <- Families.add_supervised_member(scope, child.id),
         {:ok, _email} <-
           Accounts.deliver_child_activation_instructions(
             child,
             guardian.display_name,
             &(ShareCircleWeb.Endpoint.url() <> ~p"/users/activate/#{&1}")
           ) do
      members = Families.list_members(scope)

      {:noreply,
       socket
       |> assign(:members, members)
       |> assign(:show_add_child_form, false)
       |> assign(:child_email, "")
       |> assign(:child_name, "")
       |> assign(:child_error, nil)}
    else
      {:error, %Ecto.Changeset{} = cs} ->
        msg = Enum.map_join(cs.errors, ", ", fn {field, {msg, _}} -> "#{field} #{msg}" end)
        {:noreply, assign(socket, :child_error, msg)}

      {:error, :unauthorized} ->
        {:noreply, assign(socket, :child_error, "You don't have permission to add child accounts.")}

      {:error, _} ->
        {:noreply, assign(socket, :child_error, "Something went wrong. Please try again.")}
    end
  end

  # ---------------------------------------------------------------------------
  # Promotion handlers
  # ---------------------------------------------------------------------------

  def handle_event("confirm_promote", %{"user_id" => user_id}, socket) do
    target = Enum.find(socket.assigns.members, &(&1.user_id == user_id))
    {:noreply, assign(socket, :promote_target, target)}
  end

  def handle_event("cancel_promote", _params, socket) do
    {:noreply, assign(socket, :promote_target, nil)}
  end

  def handle_event("promote_member", %{"user_id" => user_id}, socket) do
    scope = socket.assigns.current_scope
    guardian = scope.user

    with {:ok, child_user} <- fetch_promotable_child(socket.assigns.members, user_id, scope),
         {:ok, _email} <-
           Accounts.deliver_promotion_instructions(
             child_user,
             guardian.display_name,
             &(ShareCircleWeb.Endpoint.url() <> ~p"/users/promote/#{&1}")
           ) do
      {:noreply,
       socket
       |> assign(:promote_target, nil)
       |> put_flash(:info, "Promotion email sent to #{child_user.display_name}.")}
    else
      {:error, :not_found} ->
        {:noreply, assign(socket, :promote_target, nil)}

      {:error, :unauthorized} ->
        {:noreply,
         socket
         |> assign(:promote_target, nil)
         |> put_flash(:error, "You don't have permission to promote this member.")}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(:promote_target, nil)
         |> put_flash(:error, "Something went wrong. Please try again.")}
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp fetch_promotable_child(members, user_id, scope) do
    case Enum.find(members, &(&1.user_id == user_id && &1.role == "child")) do
      nil ->
        {:error, :not_found}

      membership ->
        if can_promote?(scope, membership.user) do
          {:ok, membership.user}
        else
          {:error, :unauthorized}
        end
    end
  end

  defp can_promote?(scope, child_user) do
    scope.membership.role in ["owner", "admin"] or
      scope.user.id == child_user.guardian_user_id
  end
end
