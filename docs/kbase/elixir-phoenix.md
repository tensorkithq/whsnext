# Elixir and Phoenix

## Edits under `deps/` do not survive

`mix deps.get` and `mix deps.update` overwrite `deps/` without warning. A patch made there works until the next refresh, then the bug comes back with no diff in git.

Fix: copy the library into `vendor/<name>` and point `mix.exs` at it with `path: "vendor/<name>"`. Document each patch site in the vendored README so the patches can be upstreamed or dropped later.

## A matching message can crash a guarded `handle_info`

The episode server drops pipeline messages tagged with an old beat number. A late message from a trailing task can still carry the current beat, slip past that guard, and hit a clause that has no match for it.

Fix: give every message a long-running task can send its own `handle_info` head. Put heads for messages that may straddle a state change before the stale-message guard.

## Snapshots taken at dispatch go stale

A job parked while nobody was watching kept the context it captured at the moment it was parked. Data that arrived during the wait, such as a fresh last frame, was dropped.

Fix: refresh the context when the parked job resumes, not when it was queued.

## Do not let the model's output own server state

Merging model output into server state with "updates win" lets a bad response overwrite counters the server depends on. The escalation level lives only in the GenServer and is never mirrored into model-editable state.

## Drive time with `Process.send_after` self-messages

Every phase change in the episode server is a scheduled self-message. Tests can then fire the transitions by hand instead of sleeping, and all deadlines can be sent to clients as absolute server timestamps.

## Test races on broadcast-then-write

A handler broadcast two events and then recorded a call in a test stub, all inside one `handle_info`. The test woke on the broadcast and read the stub before the write landed. It passed alone and failed under full-suite load.

Fix: before reading side effects, sync on the server, for example with `:sys.get_state/1`. That call waits until the current message finishes.

## Environment leaks into tests

The devshell sources `.env`. A set `SCRIPT_ENGINE` sent tests to a live provider instead of the `Req.Test` stub.

Fix: reset engine and provider environment variables at suite start. Tests that need one set it explicitly.

## Resolve swappable modules at call time

Reading the pipeline module from app config at call time keeps the core free of a compile-time dependency. Tests swap in a recording stub without recompiling.
