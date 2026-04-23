defmodule ShareCircle.Push do
  @moduledoc """
  Behavior for web push delivery. Implementations are selected at boot time
  via the `:push_adapter` application config.
  """

  @type subscription :: %{endpoint: String.t(), p256dh_key: String.t(), auth_key: String.t()}
  @type payload :: %{title: String.t(), body: String.t(), data: map()}

  @callback send(subscription(), payload()) :: :ok | {:error, term()}

  def send(subscription, payload) do
    adapter().send(subscription, payload)
  end

  defp adapter do
    Application.get_env(:share_circle, :push_adapter, ShareCircle.Push.Noop)
  end
end
