defmodule ShareCircle.Push.Noop do
  @moduledoc "No-op push adapter. Used in dev/test and self-hosted without push configured."

  @behaviour ShareCircle.Push

  @impl true
  def send(_subscription, _payload), do: :ok
end
