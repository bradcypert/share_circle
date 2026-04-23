defmodule ShareCircleWeb.AcceptInvitationLive do
  @moduledoc """
  Handles browser-based invitation acceptance. Accepts the token, joins the family,
  then redirects to the onboarding flow.
  """

  use ShareCircleWeb, :live_view

  alias ShareCircle.Chat
  alias ShareCircle.Families

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    scope = socket.assigns.current_scope

    case Families.accept_invitation(token, scope) do
      {:ok, membership} ->
        case Chat.ensure_family_conversation(membership.family_id) do
          {:ok, conv} ->
            Chat.add_member_to_conversation(conv.id, membership.user_id, membership.family_id)
          _ -> :ok
        end

        {:ok,
         socket
         |> put_flash(:info, "Welcome! You've joined the family.")
         |> push_navigate(to: ~p"/families/#{membership.family_id}/onboarding")}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "This invitation link is invalid.")
         |> push_navigate(to: ~p"/families")}

      {:error, :invitation_expired_or_used} ->
        {:ok,
         socket
         |> put_flash(:error, "This invitation has already been used or has expired.")
         |> push_navigate(to: ~p"/families")}

      {:error, :member_limit_reached} ->
        {:ok,
         socket
         |> put_flash(:error, "This family has reached its member limit.")
         |> push_navigate(to: ~p"/families")}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Something went wrong accepting the invitation.")
         |> push_navigate(to: ~p"/families")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center">
      <p class="text-base-content/60">Joining family...</p>
    </div>
    """
  end
end
