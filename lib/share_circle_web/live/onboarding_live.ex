defmodule ShareCircleWeb.OnboardingLive do
  @moduledoc """
  Shown to new family members after accepting an invitation.
  Lets them set their display name and get oriented before landing on the feed.
  """

  use ShareCircleWeb, :live_view

  alias ShareCircle.Accounts

  @impl true
  def mount(%{"family_id" => family_id}, _session, socket) do
    user = socket.assigns.current_scope.user

    {:ok,
     socket
     |> assign(:family_id, family_id)
     |> assign(:form, to_form(%{"display_name" => user.display_name}, as: "profile"))}
  end

  @impl true
  def handle_event("save_profile", %{"profile" => %{"display_name" => name}}, socket) do
    user = socket.assigns.current_scope.user

    case Accounts.update_user_profile(user, %{"display_name" => name}) do
      {:ok, _user} ->
        {:noreply, push_navigate(socket, to: ~p"/families/#{socket.assigns.family_id}/feed")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: "profile"))}
    end
  end

  def handle_event("skip", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/families/#{socket.assigns.family_id}/feed")}
  end
end
