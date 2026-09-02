# The devshell sources .env; a set SCRIPT_ENGINE/VIDEO_ENGINE would route
# tests at live providers instead of the stubs. Keep the suite hermetic.
System.delete_env("SCRIPT_ENGINE")
System.delete_env("VIDEO_ENGINE")

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Whn.Repo, :manual)
