defmodule ShareCircle.Posts do
  @moduledoc """
  Posts, comments, and reactions.

  Family-scoped mutations (create) require a fully loaded Scope (with family + membership).
  Single-resource mutations (update/delete) accept a Scope with only user set — they load
  the subject's family membership internally before calling Policy.authorize/3.
  """

  import Ecto.Query

  alias ShareCircle.Accounts.Scope
  alias ShareCircle.Events
  alias ShareCircle.Families
  alias ShareCircle.Families.Policy
  alias ShareCircle.Media.PostMedia
  alias ShareCircle.Notifications
  alias ShareCircle.Posts.{Comment, Post, Reaction}
  alias ShareCircle.Repo

  # ---------------------------------------------------------------------------
  # Posts
  # ---------------------------------------------------------------------------

  @doc """
  Returns a paginated list of posts for the family in the scope.
  Options: `limit` (default 25, max 100), `cursor` (opaque pagination cursor).
  Returns `{posts, pagination_meta}`.
  """
  def list_posts(%Scope{family: family}, opts \\ []) do
    limit = min(Keyword.get(opts, :limit, 25), 100)
    cursor = Keyword.get(opts, :cursor)

    query =
      from p in Post,
        where: p.family_id == ^family.id and is_nil(p.deleted_at),
        order_by: [desc: p.inserted_at, desc: p.id],
        limit: ^(limit + 1),
        preload: [:author, post_media: [media_item: :variants]]

    posts = query |> apply_cursor(cursor) |> Repo.all()
    {items, has_more} = split_page(posts, limit)
    {items, build_pagination(items, has_more)}
  end

  @doc "Returns a paginated list of posts by a specific author within the family."
  def list_posts_by_author(%Scope{family: family}, author_id, opts \\ []) do
    limit = min(Keyword.get(opts, :limit, 25), 100)
    cursor = Keyword.get(opts, :cursor)

    query =
      from p in Post,
        where: p.family_id == ^family.id and p.author_id == ^author_id and is_nil(p.deleted_at),
        order_by: [desc: p.inserted_at, desc: p.id],
        limit: ^(limit + 1),
        preload: [:author, post_media: [media_item: :variants]]

    posts = query |> apply_cursor(cursor) |> Repo.all()
    {items, has_more} = split_page(posts, limit)
    {items, build_pagination(items, has_more)}
  end

  @doc "Loads a single post, verifying the current user is a member of the post's family."
  def get_post(%Scope{user: user}, post_id) do
    with %Post{} = post <- Repo.get(Post, post_id),
         true <- is_nil(post.deleted_at),
         true <- member?(post.family_id, user.id) do
      {:ok, Repo.preload(post, [:author, post_media: [media_item: :variants]])}
    else
      nil -> {:error, :not_found}
      false -> {:error, :not_found}
    end
  end

  @doc "Creates a post. Scope must have family and membership. Accepts optional `media_ids` list."
  def create_post(%Scope{user: user, family: family, membership: membership}, attrs) do
    with :ok <- Policy.authorize(membership, :create_post),
         media_ids = Map.get(attrs, "media_ids", []),
         kind = infer_kind(attrs, media_ids),
         {:ok, post} <- insert_post(user.id, family.id, attrs, kind, media_ids) do
      Events.broadcast_to_family(family.id, :post_created, %{post: post})
      notify_family_members(family.id, user.id, "new_post", post.id, "Post")
      {:ok, post}
    end
  end

  defp insert_post(user_id, family_id, attrs, kind, media_ids) do
    Repo.transaction(fn ->
      post =
        %Post{family_id: family_id, author_id: user_id}
        |> Post.changeset(Map.put(attrs, "kind", kind))
        |> Repo.insert!()

      insert_post_media(post.id, media_ids)
      Repo.preload(post, [:author, post_media: [media_item: :variants]])
    end)
  end

  @doc "Updates a post. Scope needs only user — membership is fetched from the post's family."
  def update_post(%Scope{user: user}, post_id, attrs) do
    with {:ok, post, membership} <- load_post_with_membership(post_id, user.id),
         :ok <- Policy.authorize(membership, :update_post, post) do
      post
      |> Post.update_changeset(attrs)
      |> Repo.update()
      |> tap_broadcast(fn updated ->
        updated = Repo.preload(updated, :author)
        Events.broadcast_to_family(post.family_id, :post_updated, %{post: updated})
        updated
      end)
    end
  end

  @doc "Soft-deletes a post. Members can delete their own; admins/owners can delete any."
  def delete_post(%Scope{user: user}, post_id) do
    with {:ok, post, membership} <- load_post_with_membership(post_id, user.id),
         :ok <- Policy.authorize(membership, :delete_post, post) do
      post
      |> Ecto.Changeset.change(deleted_at: DateTime.utc_now())
      |> Repo.update()
      |> tap_broadcast(fn _ ->
        Events.broadcast_to_family(post.family_id, :post_deleted, %{post_id: post.id})
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # Comments
  # ---------------------------------------------------------------------------

  @doc "Returns a map of post_id => comment count for the given post IDs."
  def count_comments_by_post(_scope, []), do: %{}

  def count_comments_by_post(%Scope{family: family}, post_ids) do
    from(c in Comment,
      where: c.post_id in ^post_ids and c.family_id == ^family.id and is_nil(c.deleted_at),
      group_by: c.post_id,
      select: {c.post_id, count(c.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc "Returns all non-deleted comments for a post, oldest first."
  def list_comments(%Scope{user: user}, post_id) do
    with {:ok, post} <- get_visible_post(post_id, user.id) do
      comments =
        from(c in Comment,
          where: c.post_id == ^post.id and is_nil(c.deleted_at),
          order_by: [asc: c.inserted_at],
          preload: [:author]
        )
        |> Repo.all()

      {:ok, comments}
    end
  end

  @doc "Creates a comment on a post. Scope must have family and membership."
  def create_comment(
        %Scope{user: user, family: family, membership: membership},
        post_id,
        attrs
      ) do
    with :ok <- Policy.authorize(membership, :create_comment),
         {:ok, post} <- get_visible_post(post_id, user.id) do
      %Comment{family_id: family.id, post_id: post.id, author_id: user.id}
      |> Comment.changeset(attrs)
      |> Repo.insert()
      |> tap_broadcast(fn comment ->
        comment = Repo.preload(comment, :author)
        Events.broadcast_to_family(family.id, :comment_created, %{comment: comment})
        notify_post_author(post, user.id, family.id, comment)
        comment
      end)
    end
  end

  @doc "Updates a comment body. Only the author can update."
  def update_comment(%Scope{user: user}, comment_id, attrs) do
    with {:ok, comment, membership} <- load_comment_with_membership(comment_id, user.id),
         :ok <- Policy.authorize(membership, :update_comment, comment) do
      comment
      |> Comment.update_changeset(attrs)
      |> Repo.update()
      |> tap_broadcast(fn updated ->
        updated = Repo.preload(updated, :author)
        Events.broadcast_to_family(comment.family_id, :comment_updated, %{comment: updated})
        updated
      end)
    end
  end

  @doc "Soft-deletes a comment. Author or admin/owner."
  def delete_comment(%Scope{user: user}, comment_id) do
    with {:ok, comment, membership} <- load_comment_with_membership(comment_id, user.id),
         :ok <- Policy.authorize(membership, :delete_comment, comment) do
      comment
      |> Ecto.Changeset.change(deleted_at: DateTime.utc_now())
      |> Repo.update()
      |> tap_broadcast(fn _ ->
        Events.broadcast_to_family(comment.family_id, :comment_deleted, %{
          comment_id: comment.id
        })
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # Reactions
  # ---------------------------------------------------------------------------

  @doc """
  Returns a nested map of reactions for a list of posts.
  Shape: %{post_id => %{emoji => [user_id]}}
  """
  def list_reactions_for_posts(_scope, []), do: %{}

  def list_reactions_for_posts(%Scope{family: family}, post_ids) do
    from(r in Reaction,
      where: r.subject_type == "post" and r.subject_id in ^post_ids and r.family_id == ^family.id,
      select: {r.subject_id, r.emoji, r.user_id}
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn {post_id, emoji, user_id}, acc ->
      Map.update(acc, post_id, %{emoji => [user_id]}, fn emojis ->
        Map.update(emojis, emoji, [user_id], &[user_id | &1])
      end)
    end)
  end

  @doc "Adds a reaction to a post or comment. Idempotent — re-reacting with the same emoji is a no-op."
  def react(
        %Scope{user: user, family: family, membership: membership},
        subject_type,
        subject_id,
        emoji
      ) do
    with :ok <- Policy.authorize(membership, :react) do
      %Reaction{family_id: family.id, user_id: user.id}
      |> Reaction.changeset(%{subject_type: subject_type, subject_id: subject_id, emoji: emoji})
      |> Repo.insert(on_conflict: :nothing)
      |> case do
        {:ok, %Reaction{id: nil}} ->
          :ok

        {:ok, reaction} ->
          Events.broadcast_to_family(family.id, :reaction_added, %{reaction: reaction})
          :ok

        {:error, _} = err ->
          err
      end
    end
  end

  @doc "Removes a reaction. Scope must have family and membership."
  def unreact(
        %Scope{user: user, family: family, membership: membership},
        subject_type,
        subject_id,
        emoji
      ) do
    with :ok <- Policy.authorize(membership, :react) do
      case Repo.get_by(Reaction,
             user_id: user.id,
             subject_type: subject_type,
             subject_id: subject_id,
             emoji: emoji
           ) do
        nil ->
          {:error, :not_found}

        reaction ->
          {:ok, _} = Repo.delete(reaction)

          Events.broadcast_to_family(family.id, :reaction_removed, %{
            user_id: user.id,
            subject_type: subject_type,
            subject_id: subject_id,
            emoji: emoji
          })

          :ok
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp insert_post_media(_post_id, []), do: :ok

  defp insert_post_media(post_id, media_ids) do
    media_ids
    |> Enum.with_index()
    |> Enum.each(fn {media_id, i} ->
      Repo.insert!(
        PostMedia.changeset(%{post_id: post_id, media_item_id: media_id, position: i}),
        on_conflict: :nothing
      )
    end)
  end

  defp member?(family_id, user_id) do
    not is_nil(Families.get_membership_for_user(family_id, user_id))
  end

  defp get_visible_post(post_id, user_id) do
    case Repo.get(Post, post_id) do
      %Post{deleted_at: nil} = post ->
        if member?(post.family_id, user_id), do: {:ok, post}, else: {:error, :not_found}

      _ ->
        {:error, :not_found}
    end
  end

  defp load_post_with_membership(post_id, user_id) do
    case Repo.get(Post, post_id) do
      %Post{deleted_at: nil} = post ->
        case Families.get_membership_for_user(post.family_id, user_id) do
          nil -> {:error, :not_found}
          membership -> {:ok, post, membership}
        end

      _ ->
        {:error, :not_found}
    end
  end

  defp load_comment_with_membership(comment_id, user_id) do
    case Repo.get(Comment, comment_id) do
      %Comment{deleted_at: nil} = comment ->
        case Families.get_membership_for_user(comment.family_id, user_id) do
          nil -> {:error, :not_found}
          membership -> {:ok, comment, membership}
        end

      _ ->
        {:error, :not_found}
    end
  end

  defp tap_broadcast({:ok, result}, fun) do
    fun.(result)
    {:ok, result}
  end

  defp tap_broadcast(error, _fun), do: error

  defp infer_kind(%{"kind" => kind}, _media_ids) when kind in ~w(text photo video album link),
    do: kind

  defp infer_kind(_attrs, [_]), do: "photo"
  defp infer_kind(_attrs, [_ | _]), do: "album"
  defp infer_kind(_attrs, _), do: "text"

  # Cursor pagination --------------------------------------------------------

  defp apply_cursor(query, nil), do: query

  defp apply_cursor(query, cursor) do
    case decode_cursor(cursor) do
      {:ok, {ts, id}} ->
        from p in query,
          where: p.inserted_at < ^ts or (p.inserted_at == ^ts and p.id < ^id)

      :error ->
        query
    end
  end

  defp decode_cursor(cursor) do
    with {:ok, bin} <- Base.url_decode64(cursor, padding: false),
         {ts_us, id} when is_integer(ts_us) and is_binary(id) <-
           :erlang.binary_to_term(bin, [:safe]) do
      {:ok, {DateTime.from_unix!(ts_us, :microsecond), id}}
    else
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp encode_cursor(%Post{inserted_at: ts, id: id}) do
    {DateTime.to_unix(ts, :microsecond), id}
    |> :erlang.term_to_binary()
    |> Base.url_encode64(padding: false)
  end

  defp split_page(items, limit) when length(items) > limit, do: {Enum.take(items, limit), true}
  defp split_page(items, _limit), do: {items, false}

  defp build_pagination([], _has_more), do: %{cursor: nil, has_more: false}

  defp build_pagination(items, has_more),
    do: %{cursor: encode_cursor(List.last(items)), has_more: has_more}

  # Notification helpers -------------------------------------------------------

  defp notify_family_members(family_id, actor_user_id, kind, subject_id, subject_type) do
    Families.list_memberships_for_family(family_id)
    |> Enum.reject(&(&1.user_id == actor_user_id))
    |> Enum.each(fn m ->
      Notifications.notify(%{
        family_id: family_id,
        recipient_user_id: m.user_id,
        actor_user_id: actor_user_id,
        kind: kind,
        subject_type: subject_type,
        subject_id: subject_id
      })
    end)
  end

  defp notify_post_author(post, actor_user_id, family_id, comment) do
    if post.author_id != actor_user_id do
      Notifications.notify(%{
        family_id: family_id,
        recipient_user_id: post.author_id,
        actor_user_id: actor_user_id,
        kind: "new_comment",
        subject_type: "Comment",
        subject_id: comment.id,
        payload: %{preview: String.slice(comment.body, 0, 100)}
      })
    end
  end
end
