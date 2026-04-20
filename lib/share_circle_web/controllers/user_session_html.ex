defmodule ShareCircleWeb.UserSessionHTML do
  use ShareCircleWeb, :html

  embed_templates "user_session_html/*"

  defp local_mail_adapter? do
    Application.get_env(:share_circle, ShareCircle.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
