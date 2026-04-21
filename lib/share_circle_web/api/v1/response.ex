defmodule ShareCircleWeb.Api.V1.Response do
  @moduledoc """
  Helpers for building the standard JSON response envelope.

  Single resource:   %{data: ..., meta: %{request_id: ...}}
  Collection:        %{data: [...], meta: %{request_id: ..., pagination: ...}}
  Error:             %{error: %{code: ..., message: ..., request_id: ..., details: [...]}}
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  @doc "Renders a single resource wrapped in the data envelope."
  def render_data(conn, data, status \\ :ok) do
    conn
    |> put_status(status)
    |> json(%{data: data, meta: meta(conn)})
  end

  @doc """
  Renders a paginated collection.

  `pagination` should be a map with `cursor`, `has_more`, and optionally `total`.
  """
  def render_collection(conn, data, pagination) do
    conn
    |> put_status(:ok)
    |> json(%{
      data: data,
      meta: Map.merge(meta(conn), %{pagination: pagination})
    })
  end

  @doc "Renders an error envelope. `details` is an optional list of field-level errors."
  def render_error(conn, status, code, message, details \\ []) do
    error =
      %{code: code, message: message, request_id: request_id(conn)}
      |> maybe_put(:details, details)

    conn
    |> put_status(status)
    |> json(%{error: error})
    |> halt()
  end

  defp meta(conn), do: %{request_id: request_id(conn)}

  defp request_id(conn), do: conn.assigns[:request_id]

  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
