defmodule ShareCircle.FamiliesFixtures do
  @moduledoc "Test helpers for creating family-related entities."

  alias ShareCircle.Accounts.Scope
  alias ShareCircle.Families

  def unique_slug, do: "family-#{System.unique_integer([:positive])}"

  def valid_family_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{name: "Test Family", slug: unique_slug()})
  end

  def family_fixture(scope, attrs \\ %{}) do
    {:ok, {family, _membership}} =
      Families.create_family(scope, valid_family_attrs(attrs))

    family
  end

  def scope_with_family(user, _role \\ "owner") do
    {:ok, {family, membership}} =
      Families.create_family(Scope.for_user(user), valid_family_attrs())

    %{Scope.for_user(user) | family: family, membership: membership}
  end
end
