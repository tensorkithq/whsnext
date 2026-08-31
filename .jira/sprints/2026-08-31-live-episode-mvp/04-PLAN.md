---
sprint: 2026-08-31-live-episode-mvp
plan: IV
wave: II
goal: One live episode runs the full loop — a vertical scene plays, the audience votes in a server-synced 10s window, and the locked winner generates the bridge and next scene via fal — proven by passing server test suites, a timed fal spike log, migrated Postgres tables, and a production build of the web client.
worktree: false # rationale in Plan I — waves serialize merges, file claims are disjoint
branch: jira/2026-08-31-live-episode-mvp
issue: none
depends_on: [I]
parallel_with: [III, V]
files_modified:
  - server/lib/whn/application.ex
  - server/lib/whn_web/endpoint.ex
  - server/lib/whn_web/channels/user_socket.ex
  - server/lib/whn_web/channels/presence.ex
  - server/lib/whn_web/channels/episode_channel.ex
  - server/lib/whn/episode_server.ex
  - server/lib/whn/episodes.ex
  - server/test/support/channel_case.ex
  - server/test/support/pipeline_stub.ex
  - server/test/whn/episode_server_test.exs
  - server/test/whn_web/channels/episode_channel_test.exs
covers:
  - D-01
  - D-02
  - D-03
  - D-04
  - D-07
  - D-12
  - D-14
  - "RESEARCH: Presence module conventions; join reply as full sync; reply-style vote handling; Registry via-tuples + named DynamicSupervisor; Process.send_after ticks; server-owned epoch clocks; test-shaped ticks (no Process.sleep); cost-runaway guard"
  - "GOAL: audience votes in a server-synced 10s window"
effects:
  - EP-01
  - EP-02
  - EP-03
  - EP-04
  - EP-05
  - EP-06
  - EP-07
  - EP-08
  - EP-09
---

# Plan IV: Episode core — EpisodeServer, channel protocol, presence, voting

**Sprint goal:** One live episode runs the full loop — scene plays, audience votes in a server-synced 10s window, winner generates the continuation via fal — proven by tests, a spike log, migrations, and a web build.
**This plan delivers:** Track 1. The server side of the frozen wire protocol: one supervised EpisodeServer owning phases, clocks, playback, and votes; a channel that is a thin translator; Presence for viewer counts.

The wire protocol is FROZEN by `web/src/lib/types.ts` + `useEpisode.ts` — the server conforms to the client, byte for byte on event names and payload keys. `server/AGENTS.md` test rules are binding: `start_supervised!/1`, no `Process.sleep`, `:sys.get_state/1` to synchronize. The pipeline is NOT built here — dispatch goes through `Application.get_env(:whn, :pipeline_impl, Whn.Pipeline)` dynamically (no compile-time reference), tested against `PipelineStub`.

## Tasks

### I. Realtime skeleton — supervision, socket, presence

- **Files:** `server/lib/whn/application.ex`, `server/lib/whn_web/endpoint.ex`, `server/lib/whn_web/channels/user_socket.ex`, `server/lib/whn_web/channels/presence.ex`
- **Read first:** `server/lib/whn/application.ex`, `server/lib/whn_web/endpoint.ex`, `server/deps/phoenix/lib/phoenix/presence.ex` (moduledoc conventions), CONTEXT.md "Pinned interfaces" (supervision names)
- **Action:** In `application.ex`, insert after PubSub and before Endpoint: `WhnWeb.Presence`, `{Registry, keys: :unique, name: Whn.EpisodeRegistry}`, `{DynamicSupervisor, name: Whn.EpisodeSupervisor, strategy: :one_for_one}`, `{Task.Supervisor, name: Whn.TaskSupervisor}`. Create `WhnWeb.Presence` with `use Phoenix.Presence, otp_app: :whn, pubsub_server: Whn.PubSub`. Create `WhnWeb.UserSocket` (`use Phoenix.Socket`): `channel "episode:*", WhnWeb.EpisodeChannel`; `connect/3` requires `params["anon_id"]` (non-empty string; otherwise `:error`) and assigns it; `id(socket)` returns `"anon:#{anon_id}"`. In `endpoint.ex` mount `socket "/socket", WhnWeb.UserSocket, websocket: true, longpoll: false` above the LiveView comment.
- **Done when:** `(cd server && mix compile --warnings-as-errors)` exits 0; `grep 'socket "/socket"' server/lib/whn_web/endpoint.ex` matches; `grep -E 'EpisodeRegistry|EpisodeSupervisor|TaskSupervisor|WhnWeb.Presence' server/lib/whn/application.ex` shows all four.
- **Covers:** RESEARCH Presence/OTP conventions

### II. Whn.EpisodeServer + Whn.Episodes — the state machine

- **Files:** `server/lib/whn/episode_server.ex`, `server/lib/whn/episodes.ex`, `server/test/support/pipeline_stub.ex`, `server/test/whn/episode_server_test.exs`
- **Read first:** CONTEXT.md D-01/D-02/D-07/D-12/D-14 + "Pinned interfaces" (pipeline message contract, join_sync/vote signatures), `web/src/lib/types.ts` (payload shapes), `server/AGENTS.md` (OTP + test rules)
- **Action:** GenServer registered `{:via, Registry, {Whn.EpisodeRegistry, episode_id}}`, started under `Whn.EpisodeSupervisor` by `Whn.Episodes.start!(attrs)`; `Whn.Episodes.current/0` returns the pid of the single running episode (track it with a second Registry key `:current`). State: `%{id, title, premise, seed, phase, beat, playback, pending_segments, vote, votes: %{anon_id => idx}, timings, story_state, history, last_frame_url}` where `timings` defaults per D-14 (`vote_open_ms: 10_000, vote_window_ms: 10_000, segment_ms: 10_000`) and is overridable via start attrs for tests. **Opening trigger:** on `init` the server schedules `{:timeline, :presence_check}`; when the check finds ≥1 viewer (`WhnWeb.Presence.list("episode:live")` size, per D-12) and no opening has started, it invokes `pipeline_impl().start_opening(self(), ctx)` with `winning_choice: nil, last_frame_url: nil` (pinned ctx shape) exactly once and moves `idle → opening`; with 0 viewers it stays holding and reschedules the check (recheck interval from `timings`, e.g. `presence_check_ms: 3_000`). Timeline: every transition is a `{:timeline, event}` self-message scheduled with `Process.send_after` — `:vote_open` (broadcast `vote_open` with `deadline_ms = now_ms() + vote_window_ms`), `:vote_lock` (winner = max tally, ties → lowest index per D-02; broadcast `vote_locked %{winner_idx, tallies}` then `vote_closed`; invoke `pipeline_impl().start_cycle(self(), ctx)` unless viewer count is 0 per D-12 — if 0, skip and enter `:hold` with a recheck timer), `:scene_boundary` (advance to next queued playback or broadcast `phase "hold"` per D-07). `vote/3` per D-01: first write wins (`Map.put_new`), replies `{:ok, %{tallies, your_vote}}`, immediately broadcasts `vote_update %{tallies}` on accepted votes per D-03; after lock `{:error, :locked}`; no open vote `{:error, :no_open_vote}`. `join_sync/2` returns the EpisodeSync map (`now_ms` = `System.system_time(:millisecond)`; `your_vote` personalized). Handle pipeline messages `{:pipeline, beat, ...}` with a stale-beat guard (ignore `beat != state.beat`): `{:celeris, r}` stores `next_choices`/durations and merges `story_state_updates`; `{:bridge_ready, url}` queues the bridge playback; `{:segment_ready, idx, url}` appends to `pending_segments`, broadcasts `preload %{urls}` and, if phase is `hold` or `opening` with nothing playing, promotes to `playback` (broadcast `playback` + `phase "live"`); `{:error, stage, reason}` logs and holds (vote never reopens per D-15). All broadcasts via `WhnWeb.Endpoint.broadcast("episode:live", event, payload)`; every `*_ms` is absolute epoch ms. `PipelineStub` in `test/support` conforms to the pinned contract and records every invocation (`{:start_opening, ctx}` / `{:start_cycle, ctx}`) in a test Agent. Tests (`start_supervised!`, manual `send(pid, {:timeline, ...})`, `Phoenix.PubSub.subscribe(Whn.PubSub, "episode:live")` + `assert_receive`): EP-05 (open→lock ordering, deadline 10s out, lowest-index tie-break), EP-06 (boundary with nothing ready → `phase "hold"`, then `segment_ready` resumes), EP-07 (epoch-ms assertions: `deadline_ms`/`started_at_ms` within tolerance of `System.system_time(:millisecond)`), EP-08 (boot with zero presence, drive `:presence_check` and a lock — the stub Agent records NO invocation and the episode holds), EP-09 (boot with a viewer-count source reporting ≥1 — inject via a `viewer_count_fn` start attr defaulting to the Presence lookup so tests don't need real sockets — drive `:presence_check`, assert the stub recorded exactly one `{:start_opening, ctx}` with `ctx.winning_choice == nil` and `ctx.last_frame_url == nil`, and a second `:presence_check` does not re-invoke).
- **Done when:** `(cd server && mix test test/whn/episode_server_test.exs)` exits 0 covering EP-05, EP-06, EP-07, EP-08, EP-09; `grep 'start_opening' server/lib/whn/episode_server.ex` matches; `grep 'Map.put_new' server/lib/whn/episode_server.ex` (or equivalent first-write-wins) matches.
- **Covers:** D-01, D-02, D-03, D-07 (server half), D-12, D-14

### III. EpisodeChannel — thin translator over the frozen protocol

- **Files:** `server/lib/whn_web/channels/episode_channel.ex`, `server/test/support/channel_case.ex`, `server/test/whn_web/channels/episode_channel_test.exs`
- **Read first:** `web/src/lib/useEpisode.ts` (exact event names + reply shapes), `server/deps/phoenix/lib/phoenix/channel.ex` (join reply + reply-style handle_in docs), CONTEXT.md D-04
- **Action:** `join("episode:live", _params, socket)`: resolve `Whn.Episodes.current()` — if nil reply `{:error, %{reason: "no_episode"}}`; else `send(self(), :after_join)` and return `{:ok, Whn.EpisodeServer.join_sync(pid, anon_id), socket}`. Reject any other `episode:*` subtopic per D-04. `handle_info(:after_join)`: `WhnWeb.Presence.track(socket, socket.assigns.anon_id, %{online_at: System.system_time(:second)})` + `push(socket, "presence_state", WhnWeb.Presence.list(socket))`. `handle_in("vote", %{"option_idx" => idx}, socket)`: `Whn.EpisodeServer.vote(pid, anon_id, idx)` → `{:reply, {:ok, %{tallies: t, your_vote: v}}, socket}` or `{:reply, {:error, %{reason: "locked"}}, socket}` (map `:no_open_vote` to `"no_open_vote"`). Create `test/support/channel_case.ex` (standard Phoenix ChannelCase: `use Phoenix.ChannelTest, endpoint: WhnWeb.Endpoint` + Ecto sandbox setup mirroring `data_case.ex`). Tests: EP-01 (join reply has the five EpisodeSync keys), EP-02 (`assert_push "presence_state"` keyed by anon_id), EP-03 (two `push "vote"` from one socket: identical tallies, `your_vote` = first idx), EP-04 (after driving lock via the server pid, vote replies error `"locked"`).
- **Done when:** `(cd server && mix test test/whn_web/channels/episode_channel_test.exs)` exits 0 covering EP-01..EP-04; `grep 'episode:live' server/lib/whn_web/channels/episode_channel_test.exs` matches.
- **Covers:** D-01, D-04, RESEARCH join-sync/reply idioms

## Nyquist criteria for this plan

- [ ] Join reply = full EpisodeSync (EP-01)
- [ ] presence_state keyed by anon_id (EP-02)
- [ ] Immutable one-vote policy at the channel (EP-03)
- [ ] Post-lock votes rejected with "locked" (EP-04)
- [ ] Open/lock timeline + lowest-index tie-break (EP-05)
- [ ] Hold enters and exits as a state (EP-06)
- [ ] Absolute epoch-ms clocks in payloads (EP-07)
- [ ] Zero presence → pipeline not invoked, episode holds (EP-08)
- [ ] Viewers present → start_opening invoked once with nil winning_choice/last_frame_url (EP-09)

## Risks accepted in this plan

- No persistence here — votes/decisions live only in GenServer state until Plan VII wires `Whn.Store` (a crash before wave IV loses in-flight tallies; acceptable mid-sprint).
- The pipeline is stubbed; real celeris/bridge/segment production arrives in Plan VI and is wired in Plan VII.
- `Whn.Episodes.current/0` assumes exactly one live episode (D-04); multi-episode concurrency is a future sprint.
- Opening trigger polls presence on a timer rather than subscribing to presence diffs — up to one recheck interval of start latency; acceptable at MVP.
- Reconnect delivers full sync via join reply; client-side mid-scene seek precision is Plan II's territory.
