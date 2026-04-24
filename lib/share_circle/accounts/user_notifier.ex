defmodule ShareCircle.Accounts.UserNotifier do
  @moduledoc "Composes and delivers transactional emails."

  import Swoosh.Email

  alias ShareCircle.Accounts.User
  alias ShareCircle.Mailer

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"ShareCircle", "contact@example.com"})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Update email instructions", """

    ==============================

    Hi #{user.email},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to log in with a magic link.
  """
  def deliver_login_instructions(user, url) do
    case user do
      %User{confirmed_at: nil} -> deliver_confirmation_instructions(user, url)
      _ -> deliver_magic_link_instructions(user, url)
    end
  end

  defp deliver_magic_link_instructions(user, url) do
    deliver(user.email, "Log in instructions", """

    ==============================

    Hi #{user.email},

    You can log into your account by visiting the URL below:

    #{url}

    If you didn't request this email, please ignore this.

    ==============================
    """)
  end

  def deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Confirm your ShareCircle account", """

    ==============================

    Hi #{user.display_name},

    Please confirm your account by visiting the URL below:

    #{url}

    If you didn't create an account with us, please ignore this.

    ==============================
    """)
  end

  def deliver_invitation_instructions(recipient_email, family_name, accept_url) do
    deliver(recipient_email, "You're invited to join #{family_name} on ShareCircle", """

    ==============================

    Hi there,

    You've been invited to join #{family_name} on ShareCircle.

    Accept your invitation by visiting the link below (valid for 7 days):

    #{accept_url}

    If you don't have a ShareCircle account yet, you'll be able to create one after clicking the link.

    ==============================
    """)
  end

  def deliver_reset_password_instructions(user, url) do
    deliver(user.email, "Reset your ShareCircle password", """

    ==============================

    Hi #{user.display_name},

    You can reset your password by visiting the URL below (valid for 30 minutes):

    #{url}

    If you didn't request a reset, please ignore this.

    ==============================
    """)
  end
end
