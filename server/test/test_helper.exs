# The devshell sources .env, so engine selectors can leak into the test run
# and route script/video calls at live providers. Tests are hermetic: engines
# reset here; a test that needs one sets it explicitly and cleans up.
System.delete_env("SCRIPT_ENGINE")
System.delete_env("VIDEO_ENGINE")

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Whn.Repo, :manual)
