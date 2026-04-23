defmodule ShareCircleWeb.AppComponents do
  use Phoenix.Component

  import ShareCircleWeb.CoreComponents, only: [icon: 1]

  use Phoenix.VerifiedRoutes,
    endpoint: ShareCircleWeb.Endpoint,
    router: ShareCircleWeb.Router,
    statics: ShareCircleWeb.static_paths()

  attr :current_scope, :map, required: true
  attr :active_tab, :string, default: nil
  attr :main_class, :string, default: "overflow-y-auto"
  slot :inner_block, required: true

  def app_shell(assigns) do
    ~H"""
    <div class="fixed inset-0 z-10 flex overflow-hidden bg-base-100">
      <%!-- Desktop sidebar --%>
      <aside class="hidden md:flex w-60 flex-shrink-0 bg-base-200 border-r border-base-300 flex-col">
        <%!-- Family header --%>
        <div class="px-4 pt-5 pb-4 border-b border-base-300">
          <div class="flex items-center gap-2.5">
            <div class="w-6 h-6 rounded bg-primary flex items-center justify-center flex-shrink-0">
              <span class="text-primary-content text-xs font-bold leading-none">
                {String.first(@current_scope.family.name)}
              </span>
            </div>
            <span class="text-sm font-semibold text-base-content truncate leading-tight">
              {@current_scope.family.name}
            </span>
          </div>
        </div>

        <%!-- Navigation links --%>
        <nav class="flex-1 px-2 py-3 space-y-0.5 overflow-y-auto">
          <.nav_link
            active={@active_tab == "feed"}
            icon="hero-home"
            label="Feed"
            navigate={~p"/families/#{@current_scope.family.id}/feed"}
          />
          <.nav_link
            active={@active_tab == "chat"}
            icon="hero-chat-bubble-left-right"
            label="Chat"
            navigate={~p"/families/#{@current_scope.family.id}/chat"}
          />
          <.nav_link
            active={@active_tab == "events"}
            icon="hero-calendar-days"
            label="Events"
            navigate={~p"/families/#{@current_scope.family.id}/events"}
          />
          <.nav_link
            active={@active_tab == "members"}
            icon="hero-users"
            label="Members"
            navigate={~p"/families/#{@current_scope.family.id}/members"}
          />

          <div class="pt-2 mt-2 border-t border-base-300">
            <.nav_link
              active={@active_tab == "notifications"}
              icon="hero-bell"
              label="Notifications"
              navigate={~p"/notifications"}
            />
            <.nav_link
              active={false}
              icon="hero-cog-6-tooth"
              label="Settings"
              navigate={~p"/users/settings"}
            />
          </div>
        </nav>

        <%!-- User footer --%>
        <div class="border-t border-base-300 p-3">
          <div class="flex items-center gap-2.5 px-1 group">
            <div class="w-7 h-7 rounded-full bg-primary/15 flex items-center justify-center flex-shrink-0">
              <span class="text-xs font-semibold text-primary">
                {String.first(@current_scope.user.display_name || @current_scope.user.email)}
              </span>
            </div>
            <div class="flex-1 min-w-0">
              <p class="text-xs font-medium text-base-content truncate">
                {@current_scope.user.display_name || @current_scope.user.email}
              </p>
            </div>
            <.link
              href={~p"/users/log-out"}
              method="delete"
              class="opacity-0 group-hover:opacity-100 transition-opacity text-base-content/40 hover:text-base-content/70"
              title="Log out"
            >
              <.icon name="hero-arrow-right-on-rectangle" class="size-4" />
            </.link>
          </div>
        </div>
      </aside>

      <%!-- Main content area --%>
      <div class="flex-1 flex flex-col min-w-0 overflow-hidden">
        <main class={["flex-1 pb-16 md:pb-0", @main_class]}>
          {render_slot(@inner_block)}
        </main>
      </div>

      <%!-- Mobile bottom tab bar --%>
      <nav class="md:hidden fixed bottom-0 left-0 right-0 z-50 bg-base-100/95 backdrop-blur-sm border-t border-base-300">
        <div class="flex justify-around py-1.5">
          <.tab_link
            active={@active_tab == "feed"}
            icon="hero-home"
            label="Feed"
            navigate={~p"/families/#{@current_scope.family.id}/feed"}
          />
          <.tab_link
            active={@active_tab == "chat"}
            icon="hero-chat-bubble-left-right"
            label="Chat"
            navigate={~p"/families/#{@current_scope.family.id}/chat"}
          />
          <.tab_link
            active={@active_tab == "events"}
            icon="hero-calendar-days"
            label="Events"
            navigate={~p"/families/#{@current_scope.family.id}/events"}
          />
          <.tab_link
            active={@active_tab == "members"}
            icon="hero-users"
            label="Members"
            navigate={~p"/families/#{@current_scope.family.id}/members"}
          />
          <.tab_link
            active={@active_tab == "notifications"}
            icon="hero-bell"
            label="More"
            navigate={~p"/notifications"}
          />
        </div>
      </nav>
    </div>
    """
  end

  attr :active, :boolean, default: false
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :navigate, :string, required: true

  defp nav_link(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class={[
        "flex items-center gap-2.5 px-3 py-1.5 rounded-md text-sm transition-colors",
        if(@active,
          do: "bg-base-300 text-base-content font-medium",
          else: "text-base-content/55 hover:bg-base-300/60 hover:text-base-content"
        )
      ]}
    >
      <.icon name={@icon} class="size-4 flex-shrink-0" />
      {@label}
    </.link>
    """
  end

  attr :active, :boolean, default: false
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :navigate, :string, required: true

  defp tab_link(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class={[
        "flex flex-col items-center gap-0.5 px-3 py-1.5 transition-colors",
        if(@active, do: "text-primary", else: "text-base-content/45")
      ]}
    >
      <.icon name={@icon} class="size-5" />
      <span class="text-[10px] leading-none">{@label}</span>
    </.link>
    """
  end
end
