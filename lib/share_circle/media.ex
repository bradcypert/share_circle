defmodule ShareCircle.Media do
  @moduledoc """
  Manages media uploads, processing, and access.

  Two-phase upload flow:
    1. `initiate_upload/2` — validates and creates an upload session, returns a presigned PUT URL
    2. `complete_upload/2` — verifies the upload, creates a media_item, enqueues processing
  """

  import Ecto.Query

  alias ShareCircle.Accounts.Scope
  alias ShareCircle.Media.{MediaItem, MediaVariant, UploadSession}
  alias ShareCircle.Repo
  alias ShareCircle.Storage

  @allowed_mime_types ~w(
    image/jpeg image/png image/gif image/webp image/heic image/heif
    video/mp4 video/quicktime video/webm video/x-msvideo
  )

  @doc """
  Initiates an upload. Returns `{:ok, {session, put_result}}` where `put_result`
  contains the upload URL and metadata the client needs to PUT the file.
  """
  def initiate_upload(%Scope{family: family, user: user}, params) do
    with :ok <- validate_mime_type(params["mime_type"]),
         :ok <- check_quota(family, params["byte_size"]) do
      storage_key = Storage.new_key(family.id, params["mime_type"])
      expires_at = DateTime.add(DateTime.utc_now(), 3600, :second)

      session_attrs = %{
        family_id: family.id,
        user_id: user.id,
        storage_key: storage_key,
        expected_byte_size: params["byte_size"],
        expected_mime_type: params["mime_type"],
        expires_at: expires_at
      }

      with {:ok, session} <- Repo.insert(UploadSession.create_changeset(session_attrs)),
           {:ok, put_result} <-
             Storage.presigned_put(storage_key, params["mime_type"], params["byte_size"]) do
        {:ok, {session, put_result}}
      end
    end
  end

  @doc """
  Completes an upload session. Verifies the file is present in storage,
  creates a media_item, enqueues processing, and updates storage_used_bytes.
  """
  def complete_upload(%Scope{user: user, family: family}, upload_session_id) do
    with {:ok, session} <- get_pending_session(upload_session_id, family.id),
         {:ok, %{byte_size: actual_size}} <- Storage.head(session.storage_key) do
      checksum = "sha256:unknown"

      item_attrs = %{
        family_id: family.id,
        uploader_user_id: user.id,
        kind: mime_to_kind(session.expected_mime_type),
        mime_type: session.expected_mime_type,
        storage_key: session.storage_key,
        byte_size: actual_size,
        checksum: checksum
      }

      Repo.transaction(fn ->
        {:ok, item} = Repo.insert(MediaItem.create_changeset(item_attrs))

        Repo.update!(UploadSession.complete_changeset(session, item.id))

        # Update family storage used
        from(f in ShareCircle.Families.Family, where: f.id == ^family.id)
        |> Repo.update_all(inc: [storage_used_bytes: actual_size])

        # Enqueue processing
        %{media_item_id: item.id}
        |> ShareCircle.Workers.ProcessMedia.new(queue: :media)
        |> Oban.insert!()

        item
      end)
    end
  end

  @doc "Returns a short-lived download URL for the given media item."
  def get_download_url(%Scope{user: user, family: family}, media_item_id) do
    with {:ok, item} <- get_media_item(%Scope{user: user, family: family}, media_item_id) do
      Storage.presigned_get(item.storage_key, 300)
    end
  end

  @doc "Returns a download URL for a specific variant of a media item."
  def get_variant_url(%Scope{} = scope, media_item_id, variant_kind) do
    with {:ok, item} <- get_media_item(scope, media_item_id) do
      case Repo.get_by(MediaVariant, media_item_id: item.id, variant_kind: variant_kind) do
        nil -> {:error, :not_found}
        variant -> Storage.presigned_get(variant.storage_key, 300)
      end
    end
  end

  @doc "Returns a media item if the user's family owns it."
  def get_media_item(%Scope{family: family}, media_item_id) do
    item =
      from(m in MediaItem,
        where: m.id == ^media_item_id and m.family_id == ^family.id and is_nil(m.deleted_at)
      )
      |> Repo.one()

    case item do
      nil -> {:error, :not_found}
      item -> {:ok, Repo.preload(item, :variants)}
    end
  end

  defp get_pending_session(session_id, family_id) do
    session =
      from(s in UploadSession,
        where: s.id == ^session_id and s.family_id == ^family_id and is_nil(s.completed_at)
      )
      |> Repo.one()

    case session do
      nil ->
        {:error, :not_found}

      session ->
        if DateTime.compare(DateTime.utc_now(), session.expires_at) == :gt do
          {:error, :expired}
        else
          {:ok, session}
        end
    end
  end

  defp validate_mime_type(nil), do: {:error, :invalid_mime_type}

  defp validate_mime_type(mime) do
    if mime in @allowed_mime_types, do: :ok, else: {:error, :invalid_mime_type}
  end

  defp check_quota(_family, nil), do: {:error, :invalid_byte_size}

  defp check_quota(family, byte_size) when is_integer(byte_size) and byte_size > 0 do
    if family.storage_used_bytes + byte_size <= family.storage_quota_bytes do
      :ok
    else
      {:error, :quota_exceeded}
    end
  end

  defp check_quota(_family, _), do: {:error, :invalid_byte_size}

  defp mime_to_kind(mime) do
    cond do
      String.starts_with?(mime, "image/") -> "image"
      String.starts_with?(mime, "video/") -> "video"
      String.starts_with?(mime, "audio/") -> "audio"
      true -> "file"
    end
  end
end
