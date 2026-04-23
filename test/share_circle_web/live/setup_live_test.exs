defmodule ShareCircleWeb.SetupLiveTest do
  use ShareCircleWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ShareCircle.AccountsFixtures

  describe "GET /setup" do
    test "renders setup wizard when no users exist", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/setup")

      assert html =~ "Welcome to ShareCircle"
      assert html =~ "Create your admin account"
    end

    test "redirects to login when users already exist", %{conn: conn} do
      _existing = user_fixture()

      assert {:error, {:live_redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/setup")
    end

    test "advances to family step after submitting account details", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/setup")

      html =
        lv
        |> form("form", account: %{
          display_name: "Ada Lovelace",
          email: "ada@example.com",
          password: "correct-horse-battery-staple"
        })
        |> render_submit()

      assert html =~ "Set up your first family"
    end
  end
end
