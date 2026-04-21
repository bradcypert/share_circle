defmodule ShareCircle.Families.Role do
  @moduledoc "Valid membership roles and their hierarchy."

  @roles ~w(owner admin member limited)
  @type t :: String.t()

  def all, do: @roles

  def valid?(role), do: role in @roles
end
