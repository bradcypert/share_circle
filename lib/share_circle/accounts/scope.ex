defmodule ShareCircle.Accounts.Scope do
  @moduledoc """
  The authenticated context for a request or process.

  Every context function accepts a Scope as its first argument. Queries
  automatically filter by `family`, and commands verify permissions via
  `membership.role`.

  The `user` field is required for any authenticated action. `family` and
  `membership` are populated by the LoadCurrentFamily plug once the user's
  active family is resolved.
  """

  alias ShareCircle.Accounts.User

  defstruct [:user, :family, :membership, :request_id]

  @type t :: %__MODULE__{
          user: User.t() | nil,
          family: ShareCircle.Families.Family.t() | nil,
          membership: ShareCircle.Families.Membership.t() | nil,
          request_id: String.t() | nil
        }

  @doc "Builds a scope for an authenticated user (no family context yet)."
  def for_user(%User{} = user) do
    %__MODULE__{user: user}
  end

  def for_user(nil), do: nil

  @doc "Returns true if the scope has an authenticated user."
  def authenticated?(%__MODULE__{user: nil}), do: false
  def authenticated?(%__MODULE__{}), do: true

  @doc "Returns true if a family context has been loaded."
  def in_family?(%__MODULE__{family: nil}), do: false
  def in_family?(%__MODULE__{}), do: true
end
