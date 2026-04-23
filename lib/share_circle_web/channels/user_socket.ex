defmodule ShareCircleWeb.UserSocket do
  use Phoenix.Socket

  channel "family:*", ShareCircleWeb.FamilyChannel
  channel "conversation:*", ShareCircleWeb.ConversationChannel
  channel "user:*", ShareCircleWeb.UserChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Phoenix.Token.verify(ShareCircleWeb.Endpoint, "socket", token, max_age: 3600) do
      {:ok, user_id} ->
        user = ShareCircle.Accounts.get_user!(user_id)
        {:ok, assign(socket, :current_user, user)}

      {:error, _} ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(%{assigns: %{current_user: user}}), do: "user_socket:#{user.id}"
end
