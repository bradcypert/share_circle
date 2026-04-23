defmodule ShareCircleWeb.ProfileLive do
  use ShareCircleWeb, :live_view

  alias ShareCircle.Families
  alias ShareCircle.Posts

  @impl true
  def mount(%{"family_id" => family_id, "user_id" => profile_user_id}, _session, socket) do
    user = socket.assigns.current_scope.user

    case Families.get_membership_for_user(family_id, user.id) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/families")}

      %{family: family} = membership ->
        scope = %{socket.assigns.current_scope | family: family, membership: membership}

        case Families.get_membership_for_user(family_id, profile_user_id) do
          nil ->
            {:ok, push_navigate(socket, to: ~p"/families/#{family_id}/members")}

          profile_membership ->
            {posts, _pagination} = Posts.list_posts_by_author(scope, profile_user_id)

            {:ok,
             socket
             |> assign(:current_scope, scope)
             |> assign(:family_id, family_id)
             |> assign(:profile_membership, profile_membership)
             |> assign(:profile_user, profile_membership.user)
             |> assign(:posts, posts)}
        end
    end
  end
end
