defmodule ShareCircleWeb.LiveHelpers do
  @moduledoc false

  alias ShareCircle.Media

  @doc "Builds a map of media_item_id => presigned URL for all post_media in the given posts."
  def build_media_urls(scope, posts) do
    posts
    |> Enum.flat_map(fn post -> post.post_media || [] end)
    |> Enum.reduce(%{}, fn pm, acc ->
      item = pm.media_item
      variant_kind = if item.kind == "video", do: "thumb_256", else: "thumb_1024"

      case Media.get_variant_url(scope, item.id, variant_kind) do
        {:ok, url} -> Map.put(acc, item.id, url)
        {:error, _} -> acc
      end
    end)
  end

  @doc """
  Builds a map of user_id => avatar URL for a list of users.
  Skips users without an avatar_media_item_id. Falls back to the
  original file URL while the thumb_256 variant is still processing.
  """
  def build_avatar_urls(scope, users) do
    users
    |> Enum.reject(&(is_nil(&1) or is_nil(Map.get(&1, :avatar_media_item_id))))
    |> Enum.uniq_by(& &1.id)
    |> Enum.reduce(%{}, fn user, acc ->
      url =
        case Media.get_variant_url(scope, user.avatar_media_item_id, "thumb_256") do
          {:ok, url} ->
            url

          {:error, _} ->
            case Media.get_download_url(scope, user.avatar_media_item_id) do
              {:ok, url} -> url
              {:error, _} -> nil
            end
        end

      if url, do: Map.put(acc, user.id, url), else: acc
    end)
  end

  @doc "Returns the avatar URL for a single user, or nil."
  def get_user_avatar_url(scope, user) do
    build_avatar_urls(scope, [user]) |> Map.get(user.id)
  end
end
