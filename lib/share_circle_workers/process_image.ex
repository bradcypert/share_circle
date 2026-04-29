defmodule ShareCircle.Workers.ProcessImage do
  @moduledoc "Generates thumb_256 and thumb_1024 variants for image media items."

  alias ShareCircle.Media.{MediaItem, MediaVariant}
  alias ShareCircle.Repo
  alias ShareCircle.Storage
  alias ShareCircle.Storage.Local

  @variants [
    {"thumb_256", 256, :square},
    {"thumb_1024", 1024, :fit}
  ]

  def process(%MediaItem{} = item) do
    item
    |> MediaItem.update_processing_changeset("processing")
    |> Repo.update!()

    case do_process(item) do
      :ok ->
        item
        |> MediaItem.update_processing_changeset("ready")
        |> Repo.update!()

        broadcast_ready(item)
        :ok

      {:error, reason} ->
        item
        |> MediaItem.update_processing_changeset("failed", error: inspect(reason))
        |> Repo.update!()

        {:error, reason}
    end
  end

  defp do_process(item) do
    with {:ok, data} <- read_original(item),
         {:ok, vix_image} <- Vix.Vips.Image.new_from_buffer(data) do
      Enum.reduce_while(@variants, :ok, fn {kind, size, mode}, _ ->
        generate_variant_step(item, vix_image, kind, size, mode)
      end)
    end
  end

  defp generate_variant_step(item, vix_image, kind, size, mode) do
    case generate_variant(item, vix_image, kind, size, mode) do
      :ok -> {:cont, :ok}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp generate_variant(item, vix_image, kind, size, mode) do
    variant_key = variant_storage_key(item.storage_key, kind)

    with {:ok, resized} <- resize(vix_image, size, mode),
         {:ok, data} <- Vix.Vips.Image.write_to_buffer(resized, ".jpg[Q=85]"),
         :ok <- write_variant(variant_key, data) do
      width = Vix.Vips.Image.width(resized)
      height = Vix.Vips.Image.height(resized)

      Repo.insert!(
        MediaVariant.changeset(%{
          media_item_id: item.id,
          variant_kind: kind,
          storage_key: variant_key,
          mime_type: "image/jpeg",
          byte_size: Kernel.byte_size(data),
          width: width,
          height: height
        }),
        on_conflict: {:replace, [:storage_key, :byte_size, :width, :height]},
        conflict_target: [:media_item_id, :variant_kind]
      )

      :ok
    end
  end

  defp resize(image, size, :square) do
    w = Vix.Vips.Image.width(image)
    h = Vix.Vips.Image.height(image)
    min_dim = min(w, h)
    left = div(w - min_dim, 2)
    top = div(h - min_dim, 2)

    with {:ok, cropped} <- Vix.Vips.Operation.extract_area(image, left, top, min_dim, min_dim) do
      Vix.Vips.Operation.thumbnail_image(cropped, size)
    end
  end

  defp resize(image, size, :fit) do
    w = Vix.Vips.Image.width(image)
    h = Vix.Vips.Image.height(image)

    with {:ok, oriented} <- maybe_rotate(image, w, h) do
      Vix.Vips.Operation.thumbnail_image(oriented, size)
    end
  end

  defp maybe_rotate(image, w, h) when w >= h, do: {:ok, image}

  defp maybe_rotate(image, _w, _h),
    do: Vix.Vips.Operation.rot(image, :VIPS_ANGLE_D90)

  defp read_original(item) do
    case Storage.adapter() do
      Local -> Local.read(item.storage_key)
      _ -> {:error, :unsupported_adapter_for_processing}
    end
  end

  defp write_variant(key, data) do
    case Storage.adapter() do
      Local -> Local.store(key, data)
      _ -> {:error, :unsupported_adapter_for_processing}
    end
  end

  defp variant_storage_key(original_key, kind) do
    dir = Path.dirname(original_key)
    base = Path.basename(original_key, Path.extname(original_key))
    "#{dir}/#{base}_#{kind}.jpg"
  end

  defp broadcast_ready(item) do
    ShareCircle.PubSub
    |> Phoenix.PubSub.broadcast(
      "family:#{item.family_id}",
      {:media_ready, item.id}
    )
  end
end
