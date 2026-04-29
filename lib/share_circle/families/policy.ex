defmodule ShareCircle.Families.Policy do
  @moduledoc """
  Authorization policy for family-scoped actions.

  All context commands call `authorize/3` before mutating state.
  Returns `:ok` or `{:error, :unauthorized}`.
  """

  alias ShareCircle.Families.Membership

  @type action :: atom()
  @type subject :: any()

  @doc "Returns :ok if the membership permits the action, else {:error, :unauthorized}."
  def authorize(membership, action, subject \\ nil)

  # Owner can do everything
  def authorize(%Membership{role: "owner"}, _action, _subject), do: :ok

  # Admin permissions
  def authorize(%Membership{role: "admin"}, action, _subject)
      when action in [
             :update_family,
             :invite_member,
             :revoke_invitation,
             :remove_member,
             :update_member_role
           ],
      do: :ok

  def authorize(%Membership{role: "admin"}, :delete_post, _subject), do: :ok
  def authorize(%Membership{role: "admin"}, :delete_comment, _subject), do: :ok
  def authorize(%Membership{role: "admin"}, :update_event, _subject), do: :ok
  def authorize(%Membership{role: "admin"}, :delete_event, _subject), do: :ok

  # Member permissions — can mutate their own content
  def authorize(%Membership{role: "member"}, action, _subject)
      when action in [:create_post, :create_comment, :create_message, :create_event, :react],
      do: :ok

  def authorize(%Membership{role: "member", user_id: uid}, :update_post, %{author_id: uid}),
    do: :ok

  def authorize(%Membership{role: "member", user_id: uid}, :delete_post, %{author_id: uid}),
    do: :ok

  def authorize(%Membership{role: "member", user_id: uid}, :update_comment, %{author_id: uid}),
    do: :ok

  def authorize(%Membership{role: "member", user_id: uid}, :delete_comment, %{author_id: uid}),
    do: :ok

  def authorize(%Membership{role: "member", user_id: uid}, :update_event, %{author_id: uid}),
    do: :ok

  def authorize(%Membership{role: "member", user_id: uid}, :delete_event, %{author_id: uid}),
    do: :ok

  # Admin and owner may initiate promotion of a child account
  def authorize(%Membership{role: "admin"}, :promote_member, _subject), do: :ok

  # Child — same create/react rights as member, own-content edits only
  def authorize(%Membership{role: "child"}, action, _subject)
      when action in [:create_post, :create_comment, :create_message, :create_event, :react],
      do: :ok

  def authorize(%Membership{role: "child", user_id: uid}, :update_post, %{author_id: uid}),
    do: :ok

  def authorize(%Membership{role: "child", user_id: uid}, :delete_post, %{author_id: uid}),
    do: :ok

  def authorize(%Membership{role: "child", user_id: uid}, :update_comment, %{author_id: uid}),
    do: :ok

  def authorize(%Membership{role: "child", user_id: uid}, :delete_comment, %{author_id: uid}),
    do: :ok

  def authorize(%Membership{role: "child", user_id: uid}, :update_event, %{author_id: uid}),
    do: :ok

  def authorize(%Membership{role: "child", user_id: uid}, :delete_event, %{author_id: uid}),
    do: :ok

  # Limited — read only, no mutations
  def authorize(%Membership{role: "limited"}, _action, _subject), do: {:error, :unauthorized}

  # Catch-all
  def authorize(_membership, _action, _subject), do: {:error, :unauthorized}
end
