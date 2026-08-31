defmodule Whn.Repo do
  use Ecto.Repo,
    otp_app: :whn,
    adapter: Ecto.Adapters.Postgres
end
