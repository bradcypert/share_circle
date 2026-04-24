defmodule ShareCircleWeb.FeedLive do
  use ShareCircleWeb, :live_view

  alias ShareCircle.Posts
  alias ShareCircle.PubSub

  @impl true
  def mount(%{"family_id" => family_id}, _session, socket) do
    user = socket.assigns.current_scope.user

    case ShareCircle.Families.get_membership_for_user(family_id, user.id) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/families")}

      %{family: family} = membership ->
        scope = %{socket.assigns.current_scope | family: family, membership: membership}

        if connected?(socket) do
          PubSub.subscribe(PubSub.family_topic(family.id))
        end

        {posts, pagination} = Posts.list_posts(scope)
        post_ids = Enum.map(posts, & &1.id)
        comment_counts = Posts.count_comments_by_post(scope, post_ids)
        post_reactions = Posts.list_reactions_for_posts(scope, post_ids)

        {:ok,
         socket
         |> assign(:current_scope, scope)
         |> assign(:posts, posts)
         |> assign(:pagination, pagination)
         |> assign(:post_body, "")
         |> assign(:comment_counts, comment_counts)
         |> assign(:post_reactions, post_reactions)
         |> assign(:expanded_post_id, nil)
         |> assign(:expanded_comments, [])
         |> assign(:comment_body, "")
         |> assign(:editing_post_id, nil)
         |> assign(:editing_body, "")}
    end
  end

  @impl true
  def handle_event("create_post", %{"body" => body}, socket) do
    case Posts.create_post(socket.assigns.current_scope, %{"kind" => "text", "body" => body}) do
      {:ok, _post} -> {:noreply, assign(socket, :post_body, "")}
      {:error, _} -> {:noreply, socket}
    end
  end

  def handle_event("update_body", %{"value" => value}, socket) do
    {:noreply, assign(socket, :post_body, value)}
  end

  def handle_event("toggle_comments", %{"post_id" => post_id}, socket) do
    if socket.assigns.expanded_post_id == post_id do
      {:noreply,
       socket
       |> assign(:expanded_post_id, nil)
       |> assign(:expanded_comments, [])
       |> assign(:comment_body, "")}
    else
      scope = socket.assigns.current_scope

      comments =
        case Posts.list_comments(scope, post_id) do
          {:ok, list} -> list
          _ -> []
        end

      {:noreply,
       socket
       |> assign(:expanded_post_id, post_id)
       |> assign(:expanded_comments, comments)
       |> assign(:comment_body, "")}
    end
  end

  def handle_event("update_comment_body", %{"value" => value}, socket) do
    {:noreply, assign(socket, :comment_body, value)}
  end

  def handle_event("edit_post", %{"post_id" => post_id}, socket) do
    post = Enum.find(socket.assigns.posts, &(&1.id == post_id))

    {:noreply,
     socket
     |> assign(:editing_post_id, post_id)
     |> assign(:editing_body, post && post.body || "")}
  end

  def handle_event("cancel_edit_post", _params, socket) do
    {:noreply, socket |> assign(:editing_post_id, nil) |> assign(:editing_body, "")}
  end

  def handle_event("update_editing_body", %{"value" => value}, socket) do
    {:noreply, assign(socket, :editing_body, value)}
  end

  def handle_event("save_post", %{"post_id" => post_id}, socket) do
    case Posts.update_post(socket.assigns.current_scope, post_id, %{"body" => socket.assigns.editing_body}) do
      {:ok, _post} ->
        {:noreply, socket |> assign(:editing_post_id, nil) |> assign(:editing_body, "")}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("delete_post", %{"post_id" => post_id}, socket) do
    Posts.delete_post(socket.assigns.current_scope, post_id)
    {:noreply, socket}
  end

  def handle_event("toggle_reaction", %{"post_id" => post_id, "emoji" => emoji}, socket) do
    scope = socket.assigns.current_scope
    user_id = scope.user.id
    reacted = user_id in (get_in(socket.assigns.post_reactions, [post_id, emoji]) || [])

    if reacted do
      Posts.unreact(scope, "post", post_id, emoji)
    else
      Posts.react(scope, "post", post_id, emoji)
    end

    {:noreply, socket}
  end

  def handle_event("create_comment", %{"post_id" => post_id}, socket) do
    scope = socket.assigns.current_scope
    body = String.trim(socket.assigns.comment_body)

    case Posts.create_comment(scope, post_id, %{"body" => body}) do
      {:ok, _comment} -> {:noreply, assign(socket, :comment_body, "")}
      {:error, _} -> {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:post_created, %{post: post}}, socket) do
    {:noreply,
     socket
     |> update(:posts, &[post | &1])
     |> update(:comment_counts, &Map.put(&1, post.id, 0))
     |> update(:post_reactions, &Map.put(&1, post.id, %{}))}
  end

  def handle_info({:reaction_added, %{reaction: reaction}}, socket) do
    if reaction.subject_type == "post" do
      {:noreply,
       update(socket, :post_reactions, fn reactions ->
         Map.update(reactions, reaction.subject_id, %{reaction.emoji => [reaction.user_id]}, fn emojis ->
           Map.update(emojis, reaction.emoji, [reaction.user_id], &[reaction.user_id | &1])
         end)
       end)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(
        {:reaction_removed, %{subject_type: "post", subject_id: post_id, emoji: emoji, user_id: user_id}},
        socket
      ) do
    {:noreply,
     update(socket, :post_reactions, fn reactions ->
       Map.update(reactions, post_id, %{}, fn emojis ->
         updated = Map.update(emojis, emoji, [], &List.delete(&1, user_id))
         if updated[emoji] == [], do: Map.delete(updated, emoji), else: updated
       end)
     end)}
  end

  def handle_info({:post_deleted, %{post_id: id}}, socket) do
    socket =
      socket
      |> update(:posts, &Enum.reject(&1, fn p -> p.id == id end))
      |> update(:comment_counts, &Map.delete(&1, id))
      |> update(:post_reactions, &Map.delete(&1, id))

    socket =
      if socket.assigns.expanded_post_id == id do
        socket
        |> assign(:expanded_post_id, nil)
        |> assign(:expanded_comments, [])
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:post_updated, %{post: updated}}, socket) do
    {:noreply,
     update(socket, :posts, fn posts ->
       Enum.map(posts, fn p -> if p.id == updated.id, do: updated, else: p end)
     end)}
  end

  def handle_info({:comment_created, %{comment: comment}}, socket) do
    socket =
      update(socket, :comment_counts, fn counts ->
        Map.update(counts, comment.post_id, 1, &(&1 + 1))
      end)

    socket =
      if socket.assigns.expanded_post_id == comment.post_id do
        update(socket, :expanded_comments, &(&1 ++ [comment]))
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:comment_deleted, %{comment_id: id}}, socket) do
    socket =
      if socket.assigns.expanded_post_id != nil do
        deleted = Enum.find(socket.assigns.expanded_comments, &(&1.id == id))

        socket
        |> update(:expanded_comments, &Enum.reject(&1, fn c -> c.id == id end))
        |> update(:comment_counts, fn counts ->
          if deleted,
            do: Map.update(counts, deleted.post_id, 0, &max(0, &1 - 1)),
            else: counts
        end)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}
end
