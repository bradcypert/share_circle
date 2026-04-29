defmodule ShareCircleWeb.Plugs.LoadCurrentFamily do
  @moduledoc """
  Loads the family and the authenticated user's membership into the current scope.

  Expects:
  - `conn.assigns.current_scope` already populated (by AuthenticateApi or browser auth)
  - `:family_id` in path params

  On success, updates current_scope with the family and membership.
  On failure (not a member, family not found), halts with 403.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias ShareCircle.Accounts.Scope
  alias ShareCircle.Families

  def init(opts), do: opts

  def call(%{assigns: %{current_scope: %Scope{user: user} = scope}} = conn, _opts)
      when not is_nil(user) do
    family_id = conn.path_params["family_id"]

    case Families.get_membership_for_user(family_id, user.id) do
      %{family: family} = membership ->
        updated_scope = %{scope | family: family, membership: membership}
        assign(conn, :current_scope, updated_scope)

      nil ->
        forbidden(conn)
    end
  end

  def call(conn, _opts), do: forbidden(conn)

  defp forbidden(conn) do
    conn
    |> put_status(:forbidden)
    |> json(%{error: %{code: "forbidden", message: "You are not a member of this family"}})
    |> halt()
  end
end
