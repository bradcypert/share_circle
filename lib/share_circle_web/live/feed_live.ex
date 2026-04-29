defmodule ShareCircleWeb.FeedLive do
  use ShareCircleWeb, :live_view

  alias ShareCircle.Media
  alias ShareCircle.Posts
  alias ShareCircle.PubSub
  alias ShareCircleWeb.LiveHelpers

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
          Process.send_after(self(), :refresh_media_urls, 240_000)
        end

        {posts, pagination} = Posts.list_posts(scope)
        post_ids = Enum.map(posts, & &1.id)
        comment_counts = Posts.count_comments_by_post(scope, post_ids)
        post_reactions = Posts.list_reactions_for_posts(scope, post_ids)
        media_urls = build_media_urls(scope, posts)
        post_authors = Enum.map(posts, & &1.author)
        avatar_urls = build_avatar_urls(scope, [scope.user | post_authors])

        {:ok,
         socket
         |> assign(:current_scope, scope)
         |> assign(:posts, posts)
         |> assign(:pagination, pagination)
         |> assign(:post_body, "")
         |> assign(:comment_counts, comment_counts)
         |> assign(:post_reactions, post_reactions)
         |> assign(:media_urls, media_urls)
         |> assign(:avatar_urls, avatar_urls)
         |> assign(:expanded_post_id, nil)
         |> assign(:expanded_comments, [])
         |> assign(:comment_body, "")
         |> assign(:editing_post_id, nil)
         |> assign(:editing_body, "")
         |> assign(:lightbox_url, nil)
         |> allow_upload(:media,
           accept: ~w(.jpg .jpeg .png .gif .webp .heic .heif .mp4 .mov .webm .avi),
           max_entries: 4,
           max_file_size: 100_000_000,
           external: &presign_upload/2,
           auto_upload: true
         )}
    end
  end

  @impl true
  def handle_event("load_more", _params, socket) do
    scope = socket.assigns.current_scope
    cursor = socket.assigns.pagination.cursor

    {new_posts, pagination} = Posts.list_posts(scope, cursor: cursor)
    post_ids = Enum.map(new_posts, & &1.id)
    new_counts = Posts.count_comments_by_post(scope, post_ids)
    new_reactions = Posts.list_reactions_for_posts(scope, post_ids)
    new_media_urls = build_media_urls(scope, new_posts)
    new_avatar_urls = build_avatar_urls(scope, Enum.map(new_posts, & &1.author))

    {:noreply,
     socket
     |> update(:posts, &(&1 ++ new_posts))
     |> assign(:pagination, pagination)
     |> update(:comment_counts, &Map.merge(&1, new_counts))
     |> update(:post_reactions, &Map.merge(&1, new_reactions))
     |> update(:media_urls, &Map.merge(&1, new_media_urls))
     |> update(:avatar_urls, &Map.merge(&1, new_avatar_urls))}
  end

  def handle_event("validate_media", _params, socket), do: {:noreply, socket}

  def handle_event("open_lightbox", %{"url" => url}, socket) do
    {:noreply, assign(socket, :lightbox_url, url)}
  end

  def handle_event("close_lightbox", _params, socket) do
    {:noreply, assign(socket, :lightbox_url, nil)}
  end

  def handle_event("create_post", %{"body" => body}, socket) do
    scope = socket.assigns.current_scope

    media_ids =
      consume_uploaded_entries(socket, :media, fn %{session_id: session_id}, _entry ->
        case Media.complete_upload(scope, session_id) do
          {:ok, item} ->
            {:ok, item.id}

          {:error, reason} ->
            require Logger
            Logger.error("[FeedLive] complete_upload failed: #{inspect(reason)}")
            {:ok, nil}
        end
      end)
      |> Enum.reject(&is_nil/1)

    case Posts.create_post(scope, %{"body" => body, "media_ids" => media_ids}) do
      {:ok, _post} -> {:noreply, assign(socket, :post_body, "")}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not create post.")}
    end
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :media, ref)}
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

      new_avatar_urls =
        build_avatar_urls(socket.assigns.current_scope, Enum.map(comments, & &1.author))

      {:noreply,
       socket
       |> assign(:expanded_post_id, post_id)
       |> assign(:expanded_comments, comments)
       |> assign(:comment_body, "")
       |> update(:avatar_urls, &Map.merge(&1, new_avatar_urls))}
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
     |> assign(:editing_body, (post && post.body) || "")}
  end

  def handle_event("cancel_edit_post", _params, socket) do
    {:noreply, socket |> assign(:editing_post_id, nil) |> assign(:editing_body, "")}
  end

  def handle_event("update_editing_body", %{"value" => value}, socket) do
    {:noreply, assign(socket, :editing_body, value)}
  end

  def handle_event("save_post", %{"post_id" => post_id}, socket) do
    case Posts.update_post(socket.assigns.current_scope, post_id, %{
           "body" => socket.assigns.editing_body
         }) do
      {:ok, _post} ->
        {:noreply, socket |> assign(:editing_post_id, nil) |> assign(:editing_body, "")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not save post.")}
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
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not post comment.")}
    end
  end

  @impl true
  def handle_info({:post_created, %{post: post}}, socket) do
    scope = socket.assigns.current_scope
    media_urls = build_media_urls(scope, [post])
    new_avatar_urls = build_avatar_urls(scope, [post.author])

    {:noreply,
     socket
     |> update(:posts, &[post | &1])
     |> update(:comment_counts, &Map.put(&1, post.id, 0))
     |> update(:post_reactions, &Map.put(&1, post.id, %{}))
     |> update(:media_urls, &Map.merge(&1, media_urls))
     |> update(:avatar_urls, &Map.merge(&1, new_avatar_urls))}
  end

  def handle_info({:reaction_added, %{reaction: reaction}}, socket) do
    if reaction.subject_type == "post" do
      {:noreply,
       update(socket, :post_reactions, fn reactions ->
         Map.update(
           reactions,
           reaction.subject_id,
           %{reaction.emoji => [reaction.user_id]},
           fn emojis ->
             Map.update(emojis, reaction.emoji, [reaction.user_id], &[reaction.user_id | &1])
           end
         )
       end)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(
        {:reaction_removed,
         %{subject_type: "post", subject_id: post_id, emoji: emoji, user_id: user_id}},
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

    new_avatar_urls = build_avatar_urls(socket.assigns.current_scope, [comment.author])

    {:noreply, update(socket, :avatar_urls, &Map.merge(&1, new_avatar_urls))}
  end

  def handle_info({:comment_deleted, %{comment_id: id}}, socket) do
    {:noreply, maybe_remove_comment(socket, id)}
  end

  def handle_info({:media_ready, media_item_id}, socket) do
    media_item =
      socket.assigns.posts
      |> Enum.flat_map(& &1.post_media)
      |> Enum.find_value(fn pm -> pm.media_item.id == media_item_id && pm.media_item end)

    {:noreply, maybe_load_media_url(socket, media_item, media_item_id)}
  end

  def handle_info(:refresh_media_urls, socket) do
    Process.send_after(self(), :refresh_media_urls, 240_000)
    scope = socket.assigns.current_scope
    posts = socket.assigns.posts
    all_users = [scope.user | Enum.map(posts, & &1.author)]

    {:noreply,
     socket
     |> assign(:media_urls, build_media_urls(scope, posts))
     |> assign(:avatar_urls, build_avatar_urls(scope, all_users))}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp maybe_remove_comment(%{assigns: %{expanded_post_id: nil}} = socket, _id), do: socket

  defp maybe_remove_comment(socket, id) do
    deleted = Enum.find(socket.assigns.expanded_comments, &(&1.id == id))

    socket
    |> update(:expanded_comments, &Enum.reject(&1, fn c -> c.id == id end))
    |> update(:comment_counts, fn counts ->
      if deleted, do: Map.update(counts, deleted.post_id, 0, &max(0, &1 - 1)), else: counts
    end)
  end

  defp maybe_load_media_url(socket, nil, _media_item_id), do: socket

  defp maybe_load_media_url(socket, media_item, media_item_id) do
    scope = socket.assigns.current_scope
    variant_kind = if media_item.kind == "video", do: "thumb_256", else: "thumb_1024"

    case Media.get_variant_url(scope, media_item_id, variant_kind) do
      {:ok, url} -> update(socket, :media_urls, &Map.put(&1, media_item_id, url))
      {:error, _} -> socket
    end
  end

  defp presign_upload(entry, socket) do
    scope = socket.assigns.current_scope

    case Media.initiate_upload(scope, %{
           "mime_type" => entry.client_type,
           "byte_size" => entry.client_size
         }) do
      {:ok, {session, put_result}} ->
        meta = %{
          uploader: "PresignedPut",
          url: put_result.upload_url,
          headers: put_result.headers,
          session_id: session.id
        }

        {:ok, meta, socket}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_media_urls(scope, posts), do: LiveHelpers.build_media_urls(scope, posts)
  defp build_avatar_urls(scope, users), do: LiveHelpers.build_avatar_urls(scope, users)

  def upload_error_to_string(:too_large), do: "File too large (max 100 MB)"
  def upload_error_to_string(:not_accepted), do: "File type not supported"
  def upload_error_to_string(:too_many_files), do: "Too many files (max 4)"
  def upload_error_to_string(:quota_exceeded), do: "Storage quota exceeded"
  def upload_error_to_string(_), do: "Upload error"
end
