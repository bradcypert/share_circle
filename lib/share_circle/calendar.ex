defmodule ShareCircle.Calendar do
  @moduledoc """
  Calendar events and RSVPs, scoped to a family.

  Events are soft-deleted. RSVPs are upserted (one per user per event).
  """

  import Ecto.Query

  alias ShareCircle.Accounts.Scope
  alias ShareCircle.Calendar.{CalendarEvent, RSVP}
  alias ShareCircle.Events
  alias ShareCircle.Families
  alias ShareCircle.Families.Policy
  alias ShareCircle.Notifications
  alias ShareCircle.Repo

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @doc """
  Lists upcoming (and optionally past) events for the current family.

  Options:
  - `:from` — DateTime lower bound (default: beginning of today in UTC)
  - `:to`   — DateTime upper bound (optional)
  - `:limit` — max rows (default: 50)
  """
  def list_events(%Scope{family: family}, opts \\ []) do
    from_dt = Keyword.get(opts, :from, DateTime.utc_now() |> DateTime.truncate(:second))
    to_dt = Keyword.get(opts, :to)
    limit = Keyword.get(opts, :limit, 50)

    query =
      from e in CalendarEvent,
        where: e.family_id == ^family.id and is_nil(e.deleted_at),
        where: e.starts_at >= ^from_dt,
        order_by: [asc: e.starts_at],
        limit: ^limit,
        preload: [:created_by_user, :rsvps]

    query =
      if to_dt do
        where(query, [e], e.starts_at <= ^to_dt)
      else
        query
      end

    Repo.all(query)
  end

  @doc "Gets a single event by id. Returns {:ok, event} or {:error, :not_found}."
  def get_event(%Scope{family: family}, id) do
    case Repo.get_by(CalendarEvent, id: id, family_id: family.id) do
      nil -> {:error, :not_found}
      %CalendarEvent{deleted_at: nil} = event ->
        {:ok, Repo.preload(event, [:created_by_user, rsvps: :user])}
      _ -> {:error, :not_found}
    end
  end

  @doc "Creates a calendar event. Broadcasts :event_created to the family channel."
  def create_event(%Scope{user: user, family: family, membership: membership}, attrs) do
    with :ok <- Policy.authorize(membership, :create_event) do
      changeset =
        CalendarEvent.create_changeset(
          Map.merge(attrs, %{
            "family_id" => family.id,
            "created_by_user_id" => user.id
          })
        )

      case Repo.insert(changeset) do
        {:ok, event} ->
          event = Repo.preload(event, [:created_by_user, :rsvps])
          Events.broadcast_to_family(family.id, :event_created, %{event: event})
          notify_family_members_of_event(family.id, user.id, event)
          {:ok, event}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  @doc "Updates a calendar event. Only the creator or admin/owner may update."
  def update_event(%Scope{membership: membership} = scope, id, attrs) do
    with {:ok, event} <- get_event(scope, id),
         :ok <- Policy.authorize(membership, :update_event, %{author_id: event.created_by_user_id}) do
      case Repo.update(CalendarEvent.update_changeset(event, attrs)) do
        {:ok, updated} ->
          updated = Repo.preload(updated, [:created_by_user, rsvps: :user])
          Events.broadcast_to_family(scope.family.id, :event_updated, %{event: updated})
          {:ok, updated}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  @doc "Soft-deletes a calendar event."
  def delete_event(%Scope{membership: membership} = scope, id) do
    with {:ok, event} <- get_event(scope, id),
         :ok <- Policy.authorize(membership, :delete_event, %{author_id: event.created_by_user_id}) do
      now = DateTime.utc_now()
      {:ok, updated} = Repo.update(Ecto.Changeset.change(event, deleted_at: now))
      Events.broadcast_to_family(scope.family.id, :event_deleted, %{event_id: updated.id})
      {:ok, updated}
    end
  end

  # ---------------------------------------------------------------------------
  # RSVPs
  # ---------------------------------------------------------------------------

  @doc "Upserts the current user's RSVP for an event."
  def upsert_rsvp(%Scope{user: user, family: family} = scope, event_id, attrs) do
    with {:ok, _event} <- get_event(scope, event_id) do
      rsvp_attrs = Map.merge(attrs, %{
        "event_id" => event_id,
        "user_id" => user.id,
        "family_id" => family.id
      })

      changeset =
        case Repo.get_by(RSVP, event_id: event_id, user_id: user.id) do
          nil -> RSVP.changeset(%RSVP{}, rsvp_attrs)
          existing -> RSVP.changeset(existing, rsvp_attrs)
        end

      case Repo.insert_or_update(changeset) do
        {:ok, rsvp} ->
          Events.broadcast_to_family(family.id, :rsvp_updated, %{rsvp: rsvp})
          {:ok, rsvp}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  @doc "Gets the current user's RSVP for an event, or nil."
  def get_my_rsvp(%Scope{user: user}, event_id) do
    Repo.get_by(RSVP, event_id: event_id, user_id: user.id)
  end

  defp notify_family_members_of_event(family_id, actor_user_id, event) do
    Families.list_memberships_for_family(family_id)
    |> Enum.reject(&(&1.user_id == actor_user_id))
    |> Enum.each(fn m ->
      Notifications.notify(%{
        family_id: family_id,
        recipient_user_id: m.user_id,
        actor_user_id: actor_user_id,
        kind: "event_created",
        subject_type: "CalendarEvent",
        subject_id: event.id,
        payload: %{preview: event.title}
      })
    end)
  end
end
