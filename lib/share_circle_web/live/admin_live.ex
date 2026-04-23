defmodule ShareCircleWeb.AdminLive do
  use ShareCircleWeb, :live_view

  import Ecto.Query

  alias ShareCircle.Families.{Family, Membership}
  alias ShareCircle.Repo

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    unless user.is_admin do
      {:ok, push_navigate(socket, to: ~p"/families")}
    else
      {:ok,
       socket
       |> assign(:tab, :families)
       |> assign(:families, load_families())
       |> assign(:users, load_users())
       |> assign(:edit_quota, nil)
       |> assign(:quota_form, nil)}
    end
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :tab, String.to_existing_atom(tab))}
  end

  def handle_event("edit_quota", %{"id" => family_id}, socket) do
    family = Enum.find(socket.assigns.families, &(&1.id == family_id))

    form =
      to_form(
        %{
          "storage_quota_gb" => div(family.storage_quota_bytes, 1_073_741_824),
          "member_limit" => family.member_limit
        },
        as: "quota"
      )

    {:noreply, socket |> assign(:edit_quota, family_id) |> assign(:quota_form, form)}
  end

  def handle_event("cancel_quota", _params, socket) do
    {:noreply, socket |> assign(:edit_quota, nil) |> assign(:quota_form, nil)}
  end

  def handle_event("save_quota", %{"quota" => attrs}, socket) do
    family_id = socket.assigns.edit_quota
    family = Repo.get!(Family, family_id)

    storage_bytes = String.to_integer(attrs["storage_quota_gb"]) * 1_073_741_824
    member_limit = String.to_integer(attrs["member_limit"])

    family
    |> Ecto.Changeset.change(storage_quota_bytes: storage_bytes, member_limit: member_limit)
    |> Repo.update!()

    {:noreply,
     socket
     |> assign(:families, load_families())
     |> assign(:edit_quota, nil)
     |> assign(:quota_form, nil)
     |> put_flash(:info, "Quota updated.")}
  end

  def handle_event("toggle_admin", %{"id" => user_id}, socket) do
    user = Repo.get!(ShareCircle.Accounts.User, user_id)

    user
    |> Ecto.Changeset.change(is_admin: !user.is_admin)
    |> Repo.update!()

    {:noreply, assign(socket, :users, load_users())}
  end

  defp load_families do
    from(f in Family,
      where: is_nil(f.deleted_at),
      order_by: [asc: f.inserted_at]
    )
    |> Repo.all()
    |> Enum.map(fn f ->
      member_count = Repo.aggregate(from(m in Membership, where: m.family_id == ^f.id), :count)
      Map.put(f, :member_count, member_count)
    end)
  end

  defp load_users do
    from(u in ShareCircle.Accounts.User,
      where: is_nil(u.deleted_at),
      order_by: [asc: u.inserted_at]
    )
    |> Repo.all()
  end

  defp format_bytes(bytes) when bytes >= 1_073_741_824 do
    gb = Float.round(bytes / 1_073_741_824, 1)
    "#{gb} GB"
  end

  defp format_bytes(bytes) when bytes >= 1_048_576 do
    mb = Float.round(bytes / 1_048_576, 1)
    "#{mb} MB"
  end

  defp format_bytes(bytes), do: "#{bytes} B"

  defp storage_pct(used, quota) when quota > 0, do: min(round(used / quota * 100), 100)
  defp storage_pct(_, _), do: 0

  defp deployment_mode do
    Application.get_env(:share_circle, :deployment_mode, "self_hosted")
  end
end
