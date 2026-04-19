defmodule ShareCircle.Repo do
  use Ecto.Repo,
    otp_app: :share_circle,
    adapter: Ecto.Adapters.Postgres
end
