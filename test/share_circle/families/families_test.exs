defmodule ShareCircle.FamiliesTest do
  use ShareCircle.DataCase, async: true

  alias ShareCircle.Accounts.Scope
  alias ShareCircle.Families
  alias ShareCircle.Families.{Family, Membership}

  import ShareCircle.AccountsFixtures
  import ShareCircle.FamiliesFixtures

  describe "create_family/2" do
    test "creates a family and owner membership" do
      user = user_fixture()
      scope = Scope.for_user(user)

      assert {:ok, {%Family{} = family, %Membership{role: "owner"}}} =
               Families.create_family(scope, valid_family_attrs())

      assert family.name == "Test Family"
    end

    test "returns error on invalid attrs" do
      user = user_fixture()
      scope = Scope.for_user(user)
      assert {:error, _changeset} = Families.create_family(scope, %{name: ""})
    end

    test "enforces unique slug" do
      user = user_fixture()
      scope = Scope.for_user(user)
      attrs = valid_family_attrs(slug: "same-slug")
      assert {:ok, _} = Families.create_family(scope, attrs)
      assert {:error, changeset} = Families.create_family(scope, attrs)
      assert %{slug: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "list_members/1" do
    test "returns all members of the family" do
      user = user_fixture()
      scope = scope_with_family(user)
      members = Families.list_members(scope)
      assert length(members) == 1
      assert hd(members).user_id == user.id
    end
  end

  describe "invite_member/2" do
    test "creates an invitation" do
      user = user_fixture()
      scope = scope_with_family(user)

      assert {:ok, {invitation, _token}} =
               Families.invite_member(scope, %{email: "guest@example.com", role: "member"})

      assert invitation.email == "guest@example.com"
    end

    test "limited members cannot invite" do
      owner = user_fixture()
      owner_scope = scope_with_family(owner)
      limited_user = user_fixture()

      {:ok, {_inv, url_token}} =
        Families.invite_member(owner_scope, %{email: limited_user.email, role: "limited"})

      {:ok, membership} = Families.accept_invitation(url_token, Scope.for_user(limited_user))
      limited_scope = %{owner_scope | membership: membership}

      assert {:error, :unauthorized} =
               Families.invite_member(limited_scope, %{email: "other@example.com", role: "member"})
    end
  end

  describe "accept_invitation/2" do
    test "creates a membership and marks invitation accepted" do
      owner = user_fixture()
      owner_scope = scope_with_family(owner)
      new_user = user_fixture()

      {:ok, {_inv, url_token}} =
        Families.invite_member(owner_scope, %{email: new_user.email, role: "member"})

      assert {:ok, %Membership{role: "member"}} =
               Families.accept_invitation(url_token, Scope.for_user(new_user))
    end

    test "cannot accept an expired invitation" do
      owner = user_fixture()
      owner_scope = scope_with_family(owner)
      new_user = user_fixture()

      {:ok, {_inv, url_token}} =
        Families.invite_member(owner_scope, %{email: new_user.email, role: "member"})

      # Accept once — success
      assert {:ok, _} = Families.accept_invitation(url_token, Scope.for_user(new_user))

      # Accept again — should fail (already used)
      assert {:error, :invitation_expired_or_used} =
               Families.accept_invitation(url_token, Scope.for_user(new_user))
    end

    test "returns :member_limit_reached when family is at capacity" do
      owner = user_fixture()
      owner_scope = scope_with_family(owner)

      # Force member_limit to 1 (owner already occupies the slot)
      ShareCircle.Repo.update_all(
        ShareCircle.Families.Family,
        set: [member_limit: 1]
      )

      new_user = user_fixture()

      {:ok, {_inv, url_token}} =
        Families.invite_member(owner_scope, %{email: new_user.email, role: "member"})

      assert {:error, :member_limit_reached} =
               Families.accept_invitation(url_token, Scope.for_user(new_user))
    end
  end

  describe "create_family/2 quota defaults" do
    test "seeds storage_quota_bytes from STORAGE_QUOTA_GB env var" do
      System.put_env("STORAGE_QUOTA_GB", "5")

      on_exit(fn -> System.delete_env("STORAGE_QUOTA_GB") end)

      user = user_fixture()
      scope = Scope.for_user(user)
      {:ok, {family, _}} = Families.create_family(scope, valid_family_attrs())

      assert family.storage_quota_bytes == 5 * 1_073_741_824
    end

    test "seeds member_limit from MEMBER_LIMIT env var" do
      System.put_env("MEMBER_LIMIT", "25")

      on_exit(fn -> System.delete_env("MEMBER_LIMIT") end)

      user = user_fixture()
      scope = Scope.for_user(user)
      {:ok, {family, _}} = Families.create_family(scope, valid_family_attrs())

      assert family.member_limit == 25
    end

    test "uses default quota when env vars are not set" do
      System.delete_env("STORAGE_QUOTA_GB")
      System.delete_env("MEMBER_LIMIT")

      user = user_fixture()
      scope = Scope.for_user(user)
      {:ok, {family, _}} = Families.create_family(scope, valid_family_attrs())

      assert family.storage_quota_bytes == 10 * 1_073_741_824
      assert family.member_limit == 50
    end
  end
end
