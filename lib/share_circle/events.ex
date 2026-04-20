defmodule ShareCircle.Events do
  @moduledoc """
  Domain event dispatch after successful state mutations.

  Context modules call broadcast/3 after a DB transaction commits.
  Subscribers (LiveViews, channels, Oban jobs) receive {event, payload} tuples.

  Usage:

      {:ok, post} = Repo.transaction(fn -> ... end)
      Events.broadcast_to_family(scope, :post_created, %{post: post})
  """

  alias ShareCircle.PubSub

  @doc "Broadcasts a family-scoped event to all subscribers of the family topic."
  def broadcast_to_family(%{family: %{id: family_id}}, event, payload)
      when is_atom(event) do
    PubSub.broadcast(PubSub.family_topic(family_id), event, payload)
  end

  @doc "Broadcasts a conversation-scoped event."
  def broadcast_to_conversation(conversation_id, event, payload) when is_atom(event) do
    PubSub.broadcast(PubSub.conversation_topic(conversation_id), event, payload)
  end

  @doc "Broadcasts a user-scoped event (personal notifications, invites)."
  def broadcast_to_user(user_id, event, payload) when is_atom(event) do
    PubSub.broadcast(PubSub.user_topic(user_id), event, payload)
  end
end
