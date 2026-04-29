defmodule ShareCircleWeb.ChildActivationLive do
  @moduledoc """
  Handles first-time account activation for supervised (child) accounts.

  The child arrives here via a 7-day token emailed by their guardian. They set
  their own password (and optionally update their email). Their account remains
  supervised after activation — promotion to a full account is a separate step.
  """

  use ShareCircleWeb, :live_view

  alias ShareCircle.Accounts

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    {:ok,
     socket
     |> assign(:token, token)
     |> assign(:form, to_form(%{"email" => "", "password" => "", "password_confirmation" => ""}))
     |> assign(:state, :landing)
     |> assign(:error, nil)}
  end

  @impl true
  def handle_event("proceed", _params, socket) do
    {:noreply, assign(socket, :state, :set_password)}
  end

  def handle_event(
        "activate",
        %{"email" => email, "password" => password, "password_confirmation" => pw_confirm},
        socket
      ) do
    attrs = %{"email" => email, "password" => password, "password_confirmation" => pw_confirm}

    case Accounts.complete_child_activation(socket.assigns.token, attrs) do
      {:ok, user} ->
        login_token = Accounts.generate_post_activation_login_token(user)

        {:noreply,
         socket
         |> put_flash(:info, "Welcome to ShareCircle, #{user.display_name}!")
         |> redirect(to: ~p"/users/log-in/#{login_token}")}

      {:error, :invalid_or_expired_token} ->
        {:noreply,
         socket
         |> assign(:state, :expired)
         |> assign(
           :error,
           "This activation link has expired or is invalid. Ask your guardian to resend it."
         )}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, assign(socket, :form, to_form(cs, action: :validate))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200 flex items-center justify-center p-4">
      <div class="w-full max-w-md">
        <div class="text-center mb-8">
          <h1 class="text-2xl font-bold text-base-content">ShareCircle</h1>
        </div>

        <div class="bg-base-100 rounded-xl border border-base-300 p-8 space-y-6">
          <%= case @state do %>
            <% :landing -> %>
              <div class="text-center space-y-3">
                <div class="w-16 h-16 bg-primary/10 rounded-full flex items-center justify-center mx-auto">
                  <.icon name="hero-user-circle" class="size-8 text-primary" />
                </div>
                <h2 class="text-xl font-semibold text-base-content">Your account is ready</h2>
                <p class="text-sm text-base-content/60">
                  Set up your own password so only you can log in.
                </p>
              </div>
              <button phx-click="proceed" class="btn btn-primary w-full rounded-lg">
                Set up my account
              </button>
            <% :set_password -> %>
              <div class="space-y-2">
                <h2 class="text-lg font-semibold text-base-content">Choose your password</h2>
                <p class="text-sm text-base-content/60">
                  You can also update your email address below.
                </p>
              </div>

              <.form for={@form} phx-submit="activate" class="space-y-4">
                <div class="space-y-1">
                  <label class="text-xs font-medium text-base-content/60">Email address</label>
                  <.input
                    field={@form[:email]}
                    type="email"
                    placeholder="your@email.com"
                    class="w-full bg-base-200 border border-base-300 rounded-md px-3 py-2 text-sm"
                  />
                </div>

                <div class="space-y-1">
                  <label class="text-xs font-medium text-base-content/60">New password</label>
                  <.input
                    field={@form[:password]}
                    type="password"
                    placeholder="At least 12 characters"
                    class="w-full bg-base-200 border border-base-300 rounded-md px-3 py-2 text-sm"
                  />
                </div>

                <div class="space-y-1">
                  <label class="text-xs font-medium text-base-content/60">Confirm password</label>
                  <.input
                    field={@form[:password_confirmation]}
                    type="password"
                    placeholder="Same password again"
                    class="w-full bg-base-200 border border-base-300 rounded-md px-3 py-2 text-sm"
                  />
                </div>

                <button type="submit" class="btn btn-primary w-full rounded-lg">
                  Activate my account
                </button>
              </.form>
            <% :expired -> %>
              <div class="text-center space-y-3">
                <div class="w-16 h-16 bg-error/10 rounded-full flex items-center justify-center mx-auto">
                  <.icon name="hero-exclamation-circle" class="size-8 text-error" />
                </div>
                <h2 class="text-lg font-semibold text-base-content">Link expired</h2>
                <p class="text-sm text-base-content/60">{@error}</p>
              </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
