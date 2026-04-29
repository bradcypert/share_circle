defmodule ShareCircleWeb.ProfileLive do
  use ShareCircleWeb, :live_view

  alias ShareCircle.Accounts
  alias ShareCircle.Families
  alias ShareCircle.Media
  alias ShareCircle.Posts
  alias ShareCircle.PubSub
  alias ShareCircleWeb.LiveHelpers

  @impl true
  def mount(%{"family_id" => family_id, "user_id" => profile_user_id}, _session, socket) do
    user = socket.assigns.current_scope.user

    case Families.get_membership_for_user(family_id, user.id) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/families")}

      %{family: family} = membership ->
        scope = %{socket.assigns.current_scope | family: family, membership: membership}
        mount_profile(socket, scope, family_id, profile_user_id)
    end
  end

  defp mount_profile(socket, scope, family_id, profile_user_id) do
    case Families.get_membership_for_user(family_id, profile_user_id) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/families/#{family_id}/members")}

      profile_membership ->
        profile_user = Accounts.get_user!(profile_user_id)
        is_own_profile = profile_user.id == scope.user.id

        if connected?(socket) do
          PubSub.subscribe(PubSub.family_topic(scope.family.id))
          Process.send_after(self(), :refresh_media_urls, 240_000)
        end

        {posts, pagination} = Posts.list_posts_by_author(scope, profile_user_id)
        media_urls = build_media_urls(scope, posts)
        avatar_url = get_avatar_url(scope, profile_user)
        cover_url = get_cover_url(scope, profile_user)

        current_avatar_url =
          if is_own_profile, do: avatar_url, else: get_avatar_url(scope, scope.user)

        {:ok,
         socket
         |> assign(:current_scope, scope)
         |> assign(:family_id, family_id)
         |> assign(:profile_membership, profile_membership)
         |> assign(:profile_user, profile_user)
         |> assign(:is_own_profile, is_own_profile)
         |> assign(:editing, false)
         |> assign(:edit_form, build_edit_form(profile_user, profile_membership))
         |> assign(:avatar_url, avatar_url)
         |> assign(:cover_url, cover_url)
         |> assign(:current_avatar_url, current_avatar_url)
         |> assign(:posts, posts)
         |> assign(:pagination, pagination)
         |> assign(:media_urls, media_urls)
         |> assign(:lightbox_url, nil)
         |> allow_upload(:avatar,
           accept: ~w(.jpg .jpeg .png .gif .webp .heic .heif),
           max_entries: 1,
           max_file_size: 20_000_000,
           external: &presign_upload/2,
           auto_upload: true,
           progress: &handle_progress/3
         )
         |> allow_upload(:cover,
           accept: ~w(.jpg .jpeg .png .gif .webp .heic .heif),
           max_entries: 1,
           max_file_size: 20_000_000,
           external: &presign_upload/2,
           auto_upload: true,
           progress: &handle_progress/3
         )}
    end
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("start_editing", _params, socket) do
    {:noreply, assign(socket, :editing, true)}
  end

  def handle_event("cancel_editing", _params, socket) do
    user = socket.assigns.profile_user
    membership = socket.assigns.profile_membership

    {:noreply,
     socket |> assign(:editing, false) |> assign(:edit_form, build_edit_form(user, membership))}
  end

  def handle_event("save_profile", %{"profile" => params}, socket) do
    user = socket.assigns.profile_user
    scope = socket.assigns.current_scope

    with {:ok, updated_user} <- Accounts.update_user_profile(user, params),
         {:ok, updated_membership} <-
           Families.update_membership_label(scope, params["relationship_label"]) do
      {:noreply,
       socket
       |> assign(:editing, false)
       |> assign(:profile_user, updated_user)
       |> assign(:profile_membership, updated_membership)
       |> assign(:edit_form, build_edit_form(updated_user, updated_membership))
       |> put_flash(:info, "Profile updated.")}
    else
      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not save profile.")}
    end
  end

  # No-op: upload is now consumed in handle_progress when entry.done? is true
  def handle_event("upload_avatar", _params, socket), do: {:noreply, socket}
  def handle_event("upload_cover", _params, socket), do: {:noreply, socket}

  def handle_event("pin_post", %{"post_id" => post_id}, socket) do
    user = socket.assigns.profile_user

    case Accounts.update_user_profile(user, %{"pinned_post_id" => post_id}) do
      {:ok, updated_user} ->
        {:noreply, assign(socket, :profile_user, updated_user)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not pin post.")}
    end
  end

  def handle_event("unpin_post", _params, socket) do
    user = socket.assigns.profile_user

    case Accounts.update_user_profile(user, %{"pinned_post_id" => nil}) do
      {:ok, updated_user} ->
        {:noreply, assign(socket, :profile_user, updated_user)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not unpin post.")}
    end
  end

  def handle_event("validate_avatar", _params, socket), do: {:noreply, socket}
  def handle_event("validate_cover", _params, socket), do: {:noreply, socket}
  def handle_event("validate_profile", _params, socket), do: {:noreply, socket}

  def handle_event("open_lightbox", %{"url" => url}, socket) do
    {:noreply, assign(socket, :lightbox_url, url)}
  end

  def handle_event("close_lightbox", _params, socket) do
    {:noreply, assign(socket, :lightbox_url, nil)}
  end

  def handle_event("load_more", _params, socket) do
    scope = socket.assigns.current_scope
    cursor = socket.assigns.pagination.cursor

    {new_posts, pagination} =
      Posts.list_posts_by_author(scope, socket.assigns.profile_user.id, cursor: cursor)

    {:noreply,
     socket
     |> update(:posts, &(&1 ++ new_posts))
     |> assign(:pagination, pagination)
     |> update(:media_urls, &Map.merge(&1, build_media_urls(scope, new_posts)))}
  end

  # ---------------------------------------------------------------------------
  # Upload progress — consume entries as soon as they finish uploading
  # ---------------------------------------------------------------------------

  defp handle_progress(:avatar, %{done?: true} = entry, socket) do
    scope = socket.assigns.current_scope
    user = socket.assigns.profile_user

    # consume_uploaded_entry returns the callback's result directly (unwrapped)
    media_item_id =
      consume_uploaded_entry(socket, entry, fn %{session_id: session_id} ->
        case Media.complete_upload(scope, session_id) do
          {:ok, item} ->
            {:ok, item.id}

          {:error, reason} ->
            require Logger
            Logger.error("Avatar complete_upload failed: #{inspect(reason)}")
            {:ok, nil}
        end
      end)

    if media_item_id do
      case Accounts.update_user_profile(user, %{"avatar_media_item_id" => media_item_id}) do
        {:ok, updated_user} ->
          new_avatar_url = get_avatar_url(scope, updated_user)

          {:noreply,
           socket
           |> assign(:profile_user, updated_user)
           |> assign(:avatar_url, new_avatar_url)
           |> assign(:current_avatar_url, new_avatar_url)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not save avatar.")}
      end
    else
      {:noreply, put_flash(socket, :error, "Avatar upload failed.")}
    end
  end

  defp handle_progress(:avatar, _entry, socket), do: {:noreply, socket}

  defp handle_progress(:cover, %{done?: true} = entry, socket) do
    scope = socket.assigns.current_scope
    user = socket.assigns.profile_user

    media_item_id =
      consume_uploaded_entry(socket, entry, fn %{session_id: session_id} ->
        case Media.complete_upload(scope, session_id) do
          {:ok, item} ->
            {:ok, item.id}

          {:error, reason} ->
            require Logger
            Logger.error("Cover complete_upload failed: #{inspect(reason)}")
            {:ok, nil}
        end
      end)

    if media_item_id do
      case Accounts.update_user_profile(user, %{"cover_media_item_id" => media_item_id}) do
        {:ok, updated_user} ->
          {:noreply,
           socket
           |> assign(:profile_user, updated_user)
           |> assign(:cover_url, get_cover_url(scope, updated_user))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not save cover photo.")}
      end
    else
      {:noreply, put_flash(socket, :error, "Cover photo upload failed.")}
    end
  end

  defp handle_progress(:cover, _entry, socket), do: {:noreply, socket}

  # ---------------------------------------------------------------------------
  # Info
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info(:refresh_media_urls, socket) do
    Process.send_after(self(), :refresh_media_urls, 240_000)
    scope = socket.assigns.current_scope
    {:noreply, assign(socket, :media_urls, build_media_urls(scope, socket.assigns.posts))}
  end

  def handle_info({:media_ready, media_item_id}, socket) do
    scope = socket.assigns.current_scope

    # Refresh avatar/cover URLs if the ready item belongs to this user's profile
    user = socket.assigns.profile_user

    socket =
      cond do
        user.avatar_media_item_id == media_item_id ->
          assign(socket, :avatar_url, get_avatar_url(scope, user))

        user.cover_media_item_id == media_item_id ->
          assign(socket, :cover_url, get_cover_url(scope, user))

        true ->
          socket
      end

    {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp build_edit_form(user, membership) do
    %{
      "display_name" => user.display_name || "",
      "bio" => user.bio || "",
      "location" => user.location || "",
      "birthday" => format_birthday(user.birthday),
      "interests" => user.interests || "",
      "timezone" => user.timezone || "UTC",
      "relationship_label" => membership.relationship_label || ""
    }
  end

  defp format_birthday(nil), do: ""
  defp format_birthday(%Date{} = d), do: Date.to_iso8601(d)

  defp get_avatar_url(_scope, %{avatar_media_item_id: nil}), do: nil

  defp get_avatar_url(scope, user) do
    case Media.get_variant_url(scope, user.avatar_media_item_id, "thumb_256") do
      {:ok, url} ->
        url

      {:error, _} ->
        # Variant not yet processed — show the original while Oban runs
        case Media.get_download_url(scope, user.avatar_media_item_id) do
          {:ok, url} -> url
          {:error, _} -> nil
        end
    end
  end

  defp get_cover_url(_scope, %{cover_media_item_id: nil}), do: nil

  defp get_cover_url(scope, user) do
    case Media.get_variant_url(scope, user.cover_media_item_id, "thumb_1024") do
      {:ok, url} ->
        url

      {:error, _} ->
        case Media.get_download_url(scope, user.cover_media_item_id) do
          {:ok, url} -> url
          {:error, _} -> nil
        end
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

  def common_timezones do
    ~w(
      UTC
      America/New_York
      America/Chicago
      America/Denver
      America/Los_Angeles
      America/Anchorage
      America/Honolulu
      America/Phoenix
      America/Toronto
      America/Vancouver
      Europe/London
      Europe/Paris
      Europe/Berlin
      Europe/Rome
      Europe/Madrid
      Europe/Amsterdam
      Europe/Stockholm
      Asia/Tokyo
      Asia/Shanghai
      Asia/Singapore
      Asia/Dubai
      Asia/Kolkata
      Australia/Sydney
      Australia/Melbourne
      Pacific/Auckland
    )
  end
end
