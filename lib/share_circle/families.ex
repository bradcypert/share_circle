defmodule ShareCircle.Families do
  @moduledoc "Family management — creation, membership, and invitations."

  import Ecto.Query

  alias ShareCircle.Accounts.Scope
  alias ShareCircle.Events
  alias ShareCircle.Families.{Family, Invitation, Membership, Policy}
  alias ShareCircle.Repo

  # ---------------------------------------------------------------------------
  # Families
  # ---------------------------------------------------------------------------

  @doc "Returns the family for the current scope."
  def get_family!(%Scope{family: family}), do: family

  @doc "Creates a new family and makes the current user its owner."
  def create_family(%Scope{user: user}, attrs) do
    Repo.transaction(fn ->
      with {:ok, family} <- insert_family(attrs),
           {:ok, membership} <- insert_membership(family, user, "owner") do
        Events.broadcast_to_user(user.id, :family_created, %{family: family})
        {family, membership}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> unwrap_transaction()
  end

  @doc "Updates the family. Requires :update_family permission."
  def update_family(%Scope{membership: membership, family: family}, attrs) do
    with :ok <- Policy.authorize(membership, :update_family) do
      family
      |> Family.changeset(attrs)
      |> Repo.update()
    end
  end

  # ---------------------------------------------------------------------------
  # Members
  # ---------------------------------------------------------------------------

  @doc "Lists all active memberships for the current family."
  def list_members(%Scope{family: %{id: family_id}}) do
    Membership
    |> where(family_id: ^family_id)
    |> preload(:user)
    |> Repo.all()
  end

  @doc "Removes a member. Owners cannot be removed."
  def remove_member(%Scope{membership: membership} = scope, user_id) do
    with :ok <- Policy.authorize(membership, :remove_member),
         member when not is_nil(member) <- get_membership(scope, user_id),
         :ok <- guard_not_owner(member) do
      Repo.delete(member)
    end
  end

  @doc "Changes a member's role. Cannot demote the owner."
  def update_member_role(%Scope{membership: membership} = scope, user_id, role) do
    with :ok <- Policy.authorize(membership, :update_member_role),
         member when not is_nil(member) <- get_membership(scope, user_id),
         :ok <- guard_not_owner(member) do
      member
      |> Membership.changeset(%{role: role})
      |> Repo.update()
    end
  end

  # ---------------------------------------------------------------------------
  # Invitations
  # ---------------------------------------------------------------------------

  @doc "Sends an invitation email to the given address."
  def invite_member(%Scope{membership: membership, family: family, user: user}, attrs) do
    with :ok <- Policy.authorize(membership, :invite_member) do
      {url_token, changeset} = Invitation.build(family.id, user.id, attrs)

      with {:ok, invitation} <- Repo.insert(changeset) do
        # TODO: deliver invitation email via UserNotifier
        {:ok, {invitation, url_token}}
      end
    end
  end

  @doc "Lists pending invitations for the current family."
  def list_invitations(%Scope{family: %{id: family_id}}) do
    Invitation
    |> where(family_id: ^family_id)
    |> where([i], is_nil(i.accepted_at) and is_nil(i.revoked_at))
    |> where([i], i.expires_at > ^DateTime.utc_now())
    |> Repo.all()
  end

  @doc "Revokes a pending invitation."
  def revoke_invitation(%Scope{membership: membership, family: %{id: family_id}}, invitation_id) do
    with :ok <- Policy.authorize(membership, :revoke_invitation),
         %Invitation{} = inv <- Repo.get_by(Invitation, id: invitation_id, family_id: family_id),
         true <- Invitation.pending?(inv) do
      inv
      |> Ecto.Changeset.change(revoked_at: DateTime.utc_now(:microsecond))
      |> Repo.update()
    else
      false -> {:error, :invitation_not_pending}
      nil -> {:error, :not_found}
      error -> error
    end
  end

  @doc "Accepts an invitation by token, creating a membership for the user."
  def accept_invitation(url_token, %Scope{user: user}) do
    hashed_token = :crypto.hash(:sha256, Base.url_decode64!(url_token, padding: false))

    Repo.transaction(fn ->
      with %Invitation{} = inv <- Repo.get_by(Invitation, token: hashed_token),
           true <- Invitation.pending?(inv),
           {:ok, membership} <- insert_membership(%{id: inv.family_id}, user, inv.role),
           {:ok, _inv} <-
             inv
             |> Ecto.Changeset.change(
               accepted_at: DateTime.utc_now(:microsecond),
               accepted_by_user_id: user.id
             )
             |> Repo.update() do
        membership
      else
        nil -> Repo.rollback(:not_found)
        false -> Repo.rollback(:invitation_expired_or_used)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> unwrap_transaction()
  end

  # ---------------------------------------------------------------------------
  # Helpers for loading scope
  # ---------------------------------------------------------------------------

  @doc "Loads the family and membership for a user, used to populate Scope."
  def get_membership_for_user(family_id, user_id) do
    Membership
    |> where(family_id: ^family_id, user_id: ^user_id)
    |> preload(:family)
    |> Repo.one()
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp insert_family(attrs) do
    %Family{}
    |> Family.changeset(attrs)
    |> Repo.insert()
  end

  defp insert_membership(%{id: family_id}, %{id: user_id}, role) do
    %Membership{}
    |> Membership.changeset(%{role: role})
    |> Ecto.Changeset.put_change(:family_id, family_id)
    |> Ecto.Changeset.put_change(:user_id, user_id)
    |> Ecto.Changeset.put_change(:joined_at, DateTime.utc_now(:microsecond))
    |> Repo.insert()
  end

  defp get_membership(%Scope{family: %{id: family_id}}, user_id) do
    Repo.get_by(Membership, family_id: family_id, user_id: user_id)
  end

  defp guard_not_owner(%Membership{role: "owner"}), do: {:error, :cannot_modify_owner}
  defp guard_not_owner(_), do: :ok

  defp unwrap_transaction({:ok, result}), do: {:ok, result}
  defp unwrap_transaction({:error, reason}), do: {:error, reason}
end
