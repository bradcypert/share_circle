defmodule ShareCircleWeb.Api.V1.NotificationJSON do
  alias ShareCircle.Notifications.Notification

  def render(%Notification{} = n) do
    %{
      id: n.id,
      kind: n.kind,
      subject_type: n.subject_type,
      subject_id: n.subject_id,
      payload: n.payload,
      read_at: n.read_at,
      actor: actor(n),
      inserted_at: n.inserted_at
    }
  end

  defp actor(%{actor_user: %{id: id, display_name: name}}), do: %{id: id, display_name: name}
  defp actor(_), do: nil
end
