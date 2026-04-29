defmodule ShareCircleWeb.Api.V1.LocalBlobController do
  @moduledoc """
  Handles local-storage upload/download of binary blobs via signed tokens.
  Only active when the local storage adapter is configured.
  """

  use ShareCircleWeb, :controller

  alias ShareCircle.Storage.Local

  def upload(conn, %{"token" => token}) do
    case Local.verify_token(token, 3600) do
      {:ok, %{key: storage_key, action: "put"}} ->
        {:ok, data, conn} = Plug.Conn.read_body(conn, length: 100_000_000)
        :ok = Local.store(storage_key, data)
        send_resp(conn, 200, "")

      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Invalid or expired upload token"})
    end
  end

  def download(conn, %{"token" => token}) do
    case Local.verify_token(token) do
      {:ok, %{key: storage_key, action: "get"}} ->
        path = Local.full_path(storage_key)

        case File.read(path) do
          {:ok, data} ->
            mime = MIME.from_path(path)

            conn
            |> put_resp_content_type(mime)
            |> send_resp(200, data)

          {:error, _} ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Not found"})
        end

      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Invalid or expired token"})
    end
  end
end
