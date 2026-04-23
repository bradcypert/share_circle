defmodule ShareCircleWeb.AdminLiveTest do
  use ShareCircleWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ShareCircle.AccountsFixtures
  import ShareCircle.FamiliesFixtures

  alias ShareCircle.Accounts

  describe "GET /admin" do
    test "redirects non-admin users", %{conn: conn} do
      # First user is auto-admin; create a second one who is not
      {:ok, _admin} = Accounts.register_user(valid_user_attributes())
      {:ok, regular} = Accounts.register_user(valid_user_attributes())
      assert regular.is_admin == false

      conn = log_in_user(conn, regular)

      assert {:error, {:live_redirect, %{to: "/families"}}} = live(conn, ~p"/admin")
    end

    test "renders dashboard for admin users", %{conn: conn} do
      # First user is auto-admin
      {:ok, admin} = Accounts.register_user(valid_user_attributes())
      assert admin.is_admin == true

      conn = log_in_user(conn, admin)
      {:ok, _lv, html} = live(conn, ~p"/admin")

      assert html =~ "Admin Dashboard"
      assert html =~ "Families"
      assert html =~ "Users"
    end

    test "shows families in the families tab", %{conn: conn} do
      {:ok, admin} = Accounts.register_user(valid_user_attributes())
      admin_scope = scope_with_family(admin)
      family = admin_scope.family

      conn = log_in_user(conn, admin)
      {:ok, _lv, html} = live(conn, ~p"/admin")

      assert html =~ family.name
    end

    test "shows users in the users tab", %{conn: conn} do
      {:ok, admin} = Accounts.register_user(valid_user_attributes())

      conn = log_in_user(conn, admin)
      {:ok, lv, _html} = live(conn, ~p"/admin")

      html = lv |> element("button", "Users") |> render_click()

      assert html =~ admin.display_name
      assert html =~ admin.email
    end
  end

  describe "quota editing" do
    test "admin can update family quota limits", %{conn: conn} do
      {:ok, admin} = Accounts.register_user(valid_user_attributes())
      admin_scope = scope_with_family(admin)
      family = admin_scope.family

      conn = log_in_user(conn, admin)
      {:ok, lv, _html} = live(conn, ~p"/admin")

      lv |> element("button", "Edit limits") |> render_click()

      lv
      |> form("form", quota: %{storage_quota_gb: "20", member_limit: "100"})
      |> render_submit()

      updated = ShareCircle.Repo.get!(ShareCircle.Families.Family, family.id)
      assert updated.storage_quota_bytes == 20 * 1_073_741_824
      assert updated.member_limit == 100
    end
  end

  describe "admin toggle" do
    test "admin can promote another user to admin", %{conn: conn} do
      {:ok, admin} = Accounts.register_user(valid_user_attributes())
      {:ok, regular} = Accounts.register_user(valid_user_attributes())
      assert regular.is_admin == false

      conn = log_in_user(conn, admin)
      {:ok, lv, _html} = live(conn, ~p"/admin")

      lv |> element("button", "Users") |> render_click()

      lv
      |> element("[phx-click='toggle_admin'][phx-value-id='#{regular.id}']")
      |> render_click()

      updated = ShareCircle.Repo.get!(ShareCircle.Accounts.User, regular.id)
      assert updated.is_admin == true
    end
  end
end
