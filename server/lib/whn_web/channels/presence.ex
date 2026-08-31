defmodule WhnWeb.Presence do
  @moduledoc """
  Presence tracking for episode viewers, keyed by anonymous id.
  """

  use Phoenix.Presence,
    otp_app: :whn,
    pubsub_server: Whn.PubSub
end
