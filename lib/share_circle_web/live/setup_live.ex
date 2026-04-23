defmodule ShareCircleWeb.SetupLive do
  @moduledoc """
  First-boot setup wizard. Only accessible when no users exist in the database.
  Creates the instance admin account and their first family in one flow.
  """

  use ShareCircleWeb, :live_view

  alias ShareCircle.Accounts
  alias ShareCircle.Chat
  alias ShareCircle.Families

  @impl true
  def mount(_params, _session, socket) do
    if Accounts.count_users() > 0 do
      {:ok, push_navigate(socket, to: ~p"/users/log-in")}
    else
      {:ok,
       socket
       |> assign(:step, :account)
       |> assign(:account_form, account_form())
       |> assign(:family_form, family_form())
       |> assign(:error, nil)}
    end
  end

  @impl true
  def handle_event("save_account", %{"account" => attrs}, socket) do
    {:noreply, assign(socket, :account_form, to_form(attrs, as: "account")) |> assign(:step, :family)}
  end

  def handle_event("save_family", %{"family" => family_attrs}, socket) do
    account_attrs = socket.assigns.account_form.params

    with {:ok, user} <- Accounts.register_user_with_password(account_attrs),
         scope = %ShareCircle.Accounts.Scope{user: user},
         {:ok, {family, _membership}} <- Families.create_family(scope, family_attrs) do
      Chat.ensure_family_conversation(family.id)

      {:noreply,
       socket
       |> put_flash(:info, "Welcome to ShareCircle! Your account and family are ready.")
       |> push_navigate(to: ~p"/users/log-in")}
    else
      {:error, changeset} when is_struct(changeset, Ecto.Changeset) ->
        {:noreply, assign(socket, :error, format_errors(changeset))}

      _ ->
        {:noreply, assign(socket, :error, "Something went wrong. Please try again.")}
    end
  end

  def handle_event("back", _params, socket) do
    {:noreply, assign(socket, :step, :account)}
  end

  defp account_form, do: to_form(%{"email" => "", "display_name" => "", "password" => ""}, as: "account")
  defp family_form, do: to_form(%{"name" => "", "slug" => "", "timezone" => "UTC"}, as: "family")

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, val}, acc ->
        String.replace(acc, "%{#{key}}", to_string(val))
      end)
    end)
    |> Enum.map_join(", ", fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)
  end
end
