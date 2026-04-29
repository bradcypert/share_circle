defmodule ShareCircleWeb.EventsLive do
  use ShareCircleWeb, :live_view

  alias ShareCircle.Calendar
  alias ShareCircle.PubSub
  alias ShareCircleWeb.LiveHelpers

  @impl true
  def mount(%{"family_id" => family_id}, _session, socket) do
    user = socket.assigns.current_scope.user

    case ShareCircle.Families.get_membership_for_user(family_id, user.id) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/families")}

      %{family: family} = membership ->
        scope = %{socket.assigns.current_scope | family: family, membership: membership}

        if connected?(socket) do
          PubSub.subscribe(PubSub.family_topic(family.id))
        end

        events = Calendar.list_events(scope)

        {:ok,
         socket
         |> assign(:current_scope, scope)
         |> assign(:family_id, family_id)
         |> assign(:events, events)
         |> assign(:show_form, false)
         |> assign(:event_form, new_event_form())
         |> assign(:editing_event_id, nil)
         |> assign(:edit_form, nil)
         |> assign(:current_avatar_url, LiveHelpers.get_user_avatar_url(scope, scope.user))}
    end
  end

  @impl true
  def handle_event("toggle_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_form, !socket.assigns.show_form)
     |> assign(:editing_event_id, nil)
     |> assign(:edit_form, nil)}
  end

  def handle_event("create_event", %{"event" => attrs}, socket) do
    scope = socket.assigns.current_scope

    case Calendar.create_event(scope, attrs) do
      {:ok, _event} ->
        {:noreply,
         socket
         |> assign(:show_form, false)
         |> assign(:event_form, new_event_form())}

      {:error, _changeset} ->
        {:noreply, socket}
    end
  end

  def handle_event("edit_event", %{"event_id" => event_id}, socket) do
    event = Enum.find(socket.assigns.events, &(&1.id == event_id))

    edit_form =
      to_form(
        %{
          "title" => event.title,
          "description" => event.description || "",
          "location" => event.location || "",
          "starts_at" => DateTime.to_iso8601(event.starts_at),
          "ends_at" => (event.ends_at && DateTime.to_iso8601(event.ends_at)) || "",
          "timezone" => event.timezone || "UTC"
        },
        as: "event"
      )

    {:noreply,
     socket
     |> assign(:editing_event_id, event_id)
     |> assign(:edit_form, edit_form)
     |> assign(:show_form, false)}
  end

  def handle_event("cancel_edit_event", _params, socket) do
    {:noreply, socket |> assign(:editing_event_id, nil) |> assign(:edit_form, nil)}
  end

  def handle_event("update_event", %{"event" => attrs}, socket) do
    scope = socket.assigns.current_scope
    event_id = socket.assigns.editing_event_id

    case Calendar.update_event(scope, event_id, attrs) do
      {:ok, _event} ->
        {:noreply, socket |> assign(:editing_event_id, nil) |> assign(:edit_form, nil)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("delete_event", %{"event_id" => event_id}, socket) do
    Calendar.delete_event(socket.assigns.current_scope, event_id)
    {:noreply, socket}
  end

  def handle_event("rsvp", %{"event_id" => event_id, "status" => status}, socket) do
    scope = socket.assigns.current_scope
    Calendar.upsert_rsvp(scope, event_id, %{"status" => status})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:event_created, %{event: event}}, socket) do
    {:noreply, update(socket, :events, &insert_sorted(&1, event))}
  end

  def handle_info({:event_updated, %{event: updated}}, socket) do
    {:noreply,
     update(socket, :events, fn events ->
       Enum.map(events, fn e -> if e.id == updated.id, do: updated, else: e end)
     end)}
  end

  def handle_info({:event_deleted, %{event_id: id}}, socket) do
    {:noreply, update(socket, :events, &Enum.reject(&1, fn e -> e.id == id end))}
  end

  def handle_info({:rsvp_updated, %{rsvp: rsvp}}, socket) do
    scope = socket.assigns.current_scope
    {:noreply, update(socket, :events, &refresh_event(&1, rsvp.event_id, scope))}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp refresh_event(events, event_id, scope) do
    Enum.map(events, fn e ->
      if e.id == event_id, do: reload_event(scope, e), else: e
    end)
  end

  defp reload_event(scope, event) do
    case Calendar.get_event(scope, event.id) do
      {:ok, refreshed} -> refreshed
      _ -> event
    end
  end

  attr :form, :map, required: true

  def event_fields(assigns) do
    ~H"""
    <div class="space-y-3">
      <div class="space-y-1">
        <label class="text-xs font-medium text-base-content/60">Title</label>
        <input
          type="text"
          name={@form[:title].name}
          value={Phoenix.HTML.Form.input_value(@form, :title)}
          placeholder="What's the occasion?"
          class="w-full bg-base-200 border border-base-300 rounded-md px-3 py-2 text-sm text-base-content placeholder-base-content/35 focus:outline-none focus:border-base-content/30 transition-colors"
        />
      </div>
      <div class="space-y-1">
        <label class="text-xs font-medium text-base-content/60">Description</label>
        <input
          type="text"
          name={@form[:description].name}
          value={Phoenix.HTML.Form.input_value(@form, :description)}
          placeholder="Optional details"
          class="w-full bg-base-200 border border-base-300 rounded-md px-3 py-2 text-sm text-base-content placeholder-base-content/35 focus:outline-none focus:border-base-content/30 transition-colors"
        />
      </div>
      <div class="space-y-1">
        <label class="text-xs font-medium text-base-content/60">Location</label>
        <input
          type="text"
          name={@form[:location].name}
          value={Phoenix.HTML.Form.input_value(@form, :location)}
          placeholder="Where?"
          class="w-full bg-base-200 border border-base-300 rounded-md px-3 py-2 text-sm text-base-content placeholder-base-content/35 focus:outline-none focus:border-base-content/30 transition-colors"
        />
      </div>
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
        <div class="space-y-1">
          <label class="text-xs font-medium text-base-content/60">Starts at</label>
          <input
            type="datetime-local"
            name={@form[:starts_at].name}
            value={Phoenix.HTML.Form.input_value(@form, :starts_at)}
            class="w-full bg-base-200 border border-base-300 rounded-md px-3 py-2 text-sm text-base-content focus:outline-none focus:border-base-content/30 transition-colors"
          />
        </div>
        <div class="space-y-1">
          <label class="text-xs font-medium text-base-content/60">
            Ends at <span class="font-normal opacity-60">(optional)</span>
          </label>
          <input
            type="datetime-local"
            name={@form[:ends_at].name}
            value={Phoenix.HTML.Form.input_value(@form, :ends_at)}
            class="w-full bg-base-200 border border-base-300 rounded-md px-3 py-2 text-sm text-base-content focus:outline-none focus:border-base-content/30 transition-colors"
          />
        </div>
      </div>
      <div class="space-y-1">
        <label class="text-xs font-medium text-base-content/60">Timezone</label>
        <input
          type="text"
          name={@form[:timezone].name}
          value={Phoenix.HTML.Form.input_value(@form, :timezone)}
          placeholder="UTC"
          class="w-full bg-base-200 border border-base-300 rounded-md px-3 py-2 text-sm text-base-content placeholder-base-content/35 focus:outline-none focus:border-base-content/30 transition-colors"
        />
      </div>
    </div>
    """
  end

  defp format_datetime(dt, _tz) do
    Elixir.Calendar.strftime(dt, "%b %-d, %Y %-I:%M %p")
  end

  defp rsvp_count(%{rsvps: rsvps}, status) when is_list(rsvps) do
    Enum.count(rsvps, &(&1.status == status))
  end

  defp rsvp_count(_, _), do: 0

  defp new_event_form do
    now = DateTime.utc_now()

    to_form(
      %{
        "title" => "",
        "description" => "",
        "location" => "",
        "starts_at" => DateTime.to_iso8601(now),
        "ends_at" => "",
        "timezone" => "UTC",
        "all_day" => false
      },
      as: "event"
    )
  end

  defp insert_sorted(events, new_event) do
    [new_event | events]
    |> Enum.sort_by(& &1.starts_at, DateTime)
  end
end
