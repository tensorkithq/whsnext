---
sprint: 2026-09-02-frame-chained-continuity
plan: I
wave: I
goal: Scene-end frames chain each cycle into the next (pipeline emits {:last_frame, url}; server stores it latest-wins and seeds the next bridge ctx), vote_closed waits a scheduled 2.5s reveal after vote_locked, and the stale EP-08 predicate is superseded — proven by the server suite passing with all nine FC-/REV- predicates sensed and zero web/ changes.
worktree: false
branch: jira/2026-08-31-live-episode-mvp
issue: none
depends_on: []
parallel_with: []
files_modified:
  - server/lib/whn/episode_server.ex
  - server/test/whn/episode_server_test.exs
  - .jira/sprints/2026-08-31-live-episode-mvp/features/episode-core.feature
covers:
  - D-02
  - D-05
  - D-06
  - D-07
  - "GOAL: server stores the scene-end frame latest-wins and seeds the next cycle's bridge ctx"
  - "GOAL: vote_closed waits a scheduled reveal window after vote_locked"
  - "GOAL: stale EP-08 predicate superseded"
  - "RESEARCH: latest-wins handle_info head exempt from the beat guard, ordered before the guard pair"
  - "RESEARCH: pending_cycle ctx refreshed at dispatch"
  - "RESEARCH: reveal_ms in timings + guarded :vote_close head with fall-through; below-quorum close stays immediate"
  - "RESEARCH: episode_server_test.exs:61 assertion update (the one known break)"
effects:
  - FC-02
  - FC-03
  - FC-05
  - REV-01
  - REV-02
  - REV-03
---

# Plan I: Server — frame intake, deferred-cycle refresh, winner reveal

**Sprint goal:** see frontmatter `goal:`.
**This plan delivers:** the consumer side of frame chaining (the `{:last_frame, url}` handler and the deferred-cycle refresh), the winner-reveal delay, the one known test fix, and the EP-08 supersession comment. It MUST land before Plan II: once the pipeline emits `{:last_frame, url}`, a matching-beat message without this plan's handler falls into `handle_pipeline/2`, which has no clause for it, and crashes the EpisodeServer mid-integration-test.

**Environment:** run inside `nix develop` from the repo root; Postgres on 57432 must be up; tests via `mix test` from `/home/drew/kit/whn/server`. `Whn.PipelineStub` produces no pipeline messages by design — tests hand-send `{:pipeline, beat, message}`.

## Tasks

### I. Latest-wins frame intake and deferred-cycle refresh

- **Files:** `server/lib/whn/episode_server.ex`, `server/test/whn/episode_server_test.exs`
- **Read first:** `server/lib/whn/episode_server.ex` (whole file — clause order matters), `server/test/whn/episode_server_test.exs` (existing `open_vote/1` helper and PipelineStub assertion shapes), `.jira/sprints/2026-09-02-frame-chained-continuity/research-codebase.md` §1
- **Action:** Per D-02, insert a dedicated head between `handle_info({:timeline, event}, ...)` (currently line 116) and the beat-guard head `handle_info({:pipeline, beat, message}, %{beat: beat} = state)` (currently line 118):

  ```elixir
  # Scene-end frames are latest ground truth, not per-beat artifacts: the
  # trailing extraction can straddle the lock's beat bump, so this head is
  # exempt from the stale-beat guard below. Latest write wins.
  def handle_info({:pipeline, _beat, {:last_frame, url}}, state) do
    {:noreply, %{state | last_frame_url: url}}
  end
  ```

  Clause order is load-bearing — placed after the guard pair it would never match a current-beat message, which would instead crash in `handle_pipeline/2`. Per D-05, in the `handle_timeline(:presence_check, ...)` branch that dispatches a parked cycle (currently line 139), refresh the snapshot at dispatch:

  ```elixir
  dispatch(:start_cycle, %{state.pending_cycle | last_frame_url: state.last_frame_url})
  ```

  Add three tests to `episode_server_test.exs`, each commented with its predicate id:
  - **FC-02:** `start_episode()`, `send(pid, {:pipeline, 0, {:last_frame, "mock://scene-end.jpg"}})`, `open_vote(pid)`, two distinct votes (quorum), `send(pid, {:timeline, :vote_lock})`, `:sys.get_state(pid)`, then `assert [{:start_cycle, ctx}] = Whn.PipelineStub.calls()` and `assert ctx.last_frame_url == "mock://scene-end.jpg"`.
  - **FC-03:** `send(pid, {:pipeline, 41, {:last_frame, "mock://stale-tag.jpg"}})` while `state.beat == 0`, then `assert :sys.get_state(pid).last_frame_url == "mock://stale-tag.jpg"`.
  - **FC-05:** mirror the existing "quorum met but zero viewers at lock" test (Agent-backed `viewer_count_fn`): drive opening, open vote, two votes, viewers → 0, `:vote_lock` (ctx parks with `last_frame_url: nil`), then `send(pid, {:pipeline, 1, {:last_frame, "mock://held.jpg"}})`, viewers → 2, `:presence_check`; assert the dispatched `{:start_cycle, ctx}` carries `ctx.last_frame_url == "mock://held.jpg"` and the original `winning_choice`.
- **Done when:** `grep -n "last_frame" server/lib/whn/episode_server.ex` shows the new head at a lower line number than the beat-guard head; `mix test test/whn/episode_server_test.exs` exits 0 with the three new tests present.
- **Covers:** D-02, D-05, FC-02, FC-03, FC-05

### II. Winner reveal window

- **Files:** `server/lib/whn/episode_server.ex`, `server/test/whn/episode_server_test.exs`
- **Read first:** `server/lib/whn/episode_server.ex` (`@default_timings`, `lock_and_start_cycle/2`, the `handle_timeline` guarded-head/fall-through pairs at `:vote_lock`/`:revote`), `server/test/whn/episode_server_test.exs:42-69` (the test this changes), `server/AGENTS.md` test rules
- **Action:** Per D-06:
  1. Add `reveal_ms: 2_500` to `@default_timings`.
  2. In `lock_and_start_cycle/2`, replace `broadcast("vote_closed", %{})` (currently line 204, immediately after the `vote_locked` broadcast) with `schedule(:vote_close, state.timings.reveal_ms)`.
  3. Add after the `handle_timeline(:vote_lock, state)` fall-through (currently line 182):

     ```elixir
     defp handle_timeline(:vote_close, %{vote: %{locked: true}} = state) do
       broadcast("vote_closed", %{})
       %{state | vote: nil}
     end

     defp handle_timeline(:vote_close, state), do: state
     ```

     The `locked: true` guard is the whole revote-race defense: a reopened vote is `locked: false`, a consumed close leaves `vote: nil` — both fall through. The below-quorum branch (currently lines 174-179, immediate `vote_closed`, no `vote_locked`) stays byte-identical.
  4. Fix the known break at `episode_server_test.exs:61`: after the `vote_locked` assertion, replace the immediate `vote_closed` assertion with `refute_receive %Broadcast{event: "vote_closed"}`, keep the existing `:sys.get_state` + `PipelineStub.calls()` assertions, then `send(pid, {:timeline, :vote_close})` and `assert_receive %Broadcast{event: "vote_closed", payload: %{}}` (senses REV-01 together with the refute).
  5. Add a REV-02 test: quorum lock, drive `:vote_close` once (consumes — `vote_closed` received), drive `:vote_close` again → `refute_receive %Broadcast{event: "vote_closed"}`; then reopen (send `{:pipeline, 1, {:celeris, @celeris}}` — beat is 1 after the lock — then `{:timeline, :vote_open}`), drive `:vote_close` again → refute `vote_closed` and assert `:sys.get_state(pid).vote.locked == false` (the open poll survived).
  6. REV-03 is sensed by the existing below-quorum tests ("below quorum: poll closes without a winner…", "revote re-opens the same options…", "zero presence: pipeline is never invoked") — they must pass unchanged; do not touch them.
- **Done when:** `grep -n "reveal_ms" server/lib/whn/episode_server.ex` shows the default `2_500` and the `schedule(:vote_close, ...)` call site; `grep -c "vote_closed" server/lib/whn/episode_server.ex` still finds the below-quorum broadcast plus exactly one in the `:vote_close` handler; `mix test test/whn/episode_server_test.exs` exits 0.
- **Covers:** D-06, REV-01, REV-02, REV-03

### III. EP-08 supersession comment

- **Files:** `.jira/sprints/2026-08-31-live-episode-mvp/features/episode-core.feature`
- **Read first:** `.jira/sprints/2026-08-31-live-episode-mvp/features/episode-core.feature` (EP-08 scenario, lines 46-50), `.jira/sprints/2026-09-02-frame-chained-continuity/features/winner-reveal.feature` (REV-03, the superseding predicate)
- **Action:** Per D-07, insert exactly one comment line directly above the `@req:EP-08` tag line:

  ```gherkin
  # Superseded 2026-09-02 by @req:REV-03 (2026-09-02-frame-chained-continuity): the quorum guard (min_voters, commit ba56bb2) replaced the zero-presence hold at lock. Preserved verbatim for this sprint's claim map.
  ```

  Nothing else in the file changes — tags, Given/When/Then, and all other scenarios stay byte-identical.
- **Done when:** `grep -n "Superseded 2026-09-02 by @req:REV-03" .jira/sprints/2026-08-31-live-episode-mvp/features/episode-core.feature` matches; `git diff --stat` for that file shows exactly one line added, zero removed.
- **Covers:** D-07, GOAL: stale EP-08 predicate superseded

## Nyquist criteria for this plan

- [ ] `mix test test/whn/episode_server_test.exs` exits 0, including three new frame tests (FC-02, FC-03, FC-05) and the reveal tests (REV-01, REV-02)
- [ ] Existing below-quorum/revote tests pass byte-unchanged (REV-03)
- [ ] `mix test` (full suite) exits 0 — no pipeline change has landed yet, so this proves the new head is purely additive
- [ ] `grep -n "{:last_frame" server/lib/whn/episode_server.ex` — new head appears above the beat-guard head (FC-03)
- [ ] `grep -n "reveal_ms\|:vote_close" server/lib/whn/episode_server.ex` — timing key, schedule site, guarded head + fall-through all present (REV-01, REV-02)
- [ ] One-line supersession comment present in the old feature file; rest of the file byte-identical
- [ ] `git status --porcelain web/` prints nothing

## Risks accepted in this plan

- A vote pushed inside the reveal window after `:vote_close` consumed replies `{:error, :no_open_vote}` instead of `{:error, :locked}` — the client treats both as terminal errors; accepted.
- A scheduled `:vote_close` outliving a terminated episode is a `send_after` to a dead pid — inert; accepted.
- No monotonic beat check on frame intake: a zombie cycle can overwrite a fresher frame with a one-beat-old one in a pathological retry interleaving (bounded, per Claude's discretion in CONTEXT.md); accepted.
- The producer side of `{:last_frame, url}` does not exist yet — FC-01/FC-04/FC-06 land in Plan II (wave II); until then the head is exercised only by hand-sent test messages, by design.
