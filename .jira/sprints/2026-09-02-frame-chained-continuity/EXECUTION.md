# Execution: 2026-09-02-frame-chained-continuity

Append-only log of what happened during `/jira:execute`. The executor writes here; humans read it.

## Started

2026-09-02T00:00:00Z (Plan I executor)

## Branch / worktree

jira/2026-08-31-live-episode-mvp (no worktree; `worktree: false`)

Pre-flight note: working tree carried exactly one modification at start — `.jira/STATE.md` status flip `planned → executing` by the orchestrator itself. Not user work; proceeded without stashing and left the file untouched.

## Task log

## Plan I

### Plan I task I: Latest-wins frame intake and deferred-cycle refresh
- **Commit:** `64b37e62b3799c5522ecf17cc59d1f63c075ed12`
- **Result:** done
- **Notes:** Red-green per tdd skill: FC-02 crashed in `handle_pipeline/2` (the exact D-02 hazard), FC-03/FC-05 failed on nil, then the D-02 head (above the beat-guard pair, `episode_server.ex:121`) and the D-05 refresh at the presence-check dispatch turned all 15 tests green. Refs trailer omitted from the commit message: house git log carries no trailers and the user's global commit rules forbid internal IDs — plan/task mapping recorded here instead.

### Plan I task II: Winner reveal window
- **Commit:** `e6e43b3672d47fec4056e8c42ae2b0fa022ccf31`
- **Result:** done
- **Notes:** Red first (EP-05 test failed on the new `refute_receive vote_closed`; REV-02 crashed on the missing `:vote_close` clause), then D-06 landed: `reveal_ms: 2_500` in `@default_timings`, `schedule(:vote_close, ...)` replacing the inline close in `lock_and_start_cycle/2`, guarded `:vote_close` head + silent fall-through. Below-quorum branch byte-identical (REV-03 tests untouched and passing). Greps: exactly two `vote_closed` broadcast sites (below-quorum line 186, `:vote_close` handler line 199). 16/16 tests green.

### Plan I task III: EP-08 supersession comment
- **Commit:** `724d20230982b1b8c86fd76cd7e824644c6d823c`
- **Result:** done
- **Notes:** Exactly one comment line inserted above the `@req:EP-08` tag (D-07); `git diff --numstat` confirmed 1 insertion / 0 deletions, everything else byte-identical. Indented two spaces to match the tag line and the sibling comment style in `winner-reveal.feature`.

## Plan II

### Plan II task I: Trailing extraction and `{:last_frame, url}` emission
- **Commit:** `ff245afd85d6295fe8ae1c4c86ea91b3d6625e13`
- **Result:** done
- **Notes:** `next_frame(2, url)` now returns the final segment url; `chain_frame/3` inserted between outcome and report in both `run_cycle` and `run_opening`, calling `Whn.Frames.last_frame/1` directly (single attempt, no `with_retry` — D-03). `mix compile --warnings-as-errors` clean; existing 4 pipeline tests pass unmodified. Test-first deferred to task III by plan design (FC-01/FC-04 tests live in task III's file scope). Expected noise: CEL tests now log a best-effort extraction warning when `on_exit` removes the fixture before the detached cycle task's trailing attempt — the designed skip path, not a failure.

### Plan II task II: Audio-overhang retry in `Whn.Frames`
- **Commit:** `b3d5c748e456610c6b6699e7f48de73f57d602e2`
- **Result:** done
- **Notes:** Red-green: overhang fixture test (video 1s / audio 1.5s) failed first with `{:ffmpeg, 234, ...}` on the `-0.25` seek, then the D-04 retry (`run_ffmpeg/3` takes the `-sseof` offset; `-0.25` primary, `-1` once on nonzero exit, second result as-is) turned it green. 3/3 frames tests pass including the unreadable-video error propagation. Commit rebuilt once (originally `1c3ac8f`, local-only) to fold in `mix format` output on the new test; content otherwise identical.

### Plan II task III: `FalMock.fail_on_call/2` and the pipeline predicates
- **Commit:** `ea49caebcdbbe00c3f16d7f7dcc85d673ac9c0d5`
- **Result:** deviated (small)
- **Notes:** `fail_on_call/2` additive (`fail_on: %{}` + per-fun `counts: %{}` in Agent state, checked in a `cond` inside `dispatch/3`; `fail_once/1` untouched). FC-01 asserts `{:last_frame, url}` after `{:segment_ready, 2, _}` with `mock://frame-` url and no error; FC-04 arms upload call 4 (arithmetic documented in-test) and refutes both error and frame message. 6/6 pipeline tests — CEL-04/05/06 and the opening test byte-unmodified and passing. Commit rebuilt once (originally `21903c1`, local-only) to include the deviation below.
- **Deviation:** the trailing extraction outlives test bodies, and empirically (probe tests) BOTH `start_supervised!` processes and setup-`start_link`ed (linked) processes die with the test process BEFORE `on_exit` callbacks run — so the plan's assumption that `drain_tasks` absorbs the tail against a live mock was wrong in ordering: the tail crashed on the dead named Agent (`noproc` error logs on every full-suite run; tests still passed, and no live-fal exposure — the named-module call fails before `impl()` could ever re-resolve). Fix: `FalMock.start/1` (unlinked, additive) + a drain-then-stop teardown in `pipeline_test.exs` setup, and the same one-line `start_link → start` swap in `server/test/whn/integration_test.exs` — a file OUTSIDE this plan's `files_modified`, changed because its own `drain_tasks` had the identical dead-mock ordering. Three consecutive full-suite runs now show zero `[error]` logs.

## Nyquist results

### Plan I

- [x] `mix test test/whn/episode_server_test.exs` exits 0 with FC-02, FC-03, FC-05, REV-01 (refute + drive), REV-02 present — 16 tests, 0 failures
- [x] Below-quorum/revote tests byte-unchanged (no diff lines touch them across the three commits) and passing (REV-03)
- [x] Full `mix test` exits 0 — 45 tests, 0 failures; the `{:last_frame, _}` head is purely additive pre-pipeline-change. `mix precommit` also clean.
- [x] `grep -n "{:last_frame"` — head at `episode_server.ex:122`, beat-guard head at `:126` (FC-03 ordering)
- [x] `grep -n "reveal_ms\|:vote_close"` — `reveal_ms: 2_500` (:32), guarded head (:198), fall-through (:203), schedule site (:225); exactly two `vote_closed` broadcast sites (below-quorum :186, close handler :199)
- [x] Supersession comment at `episode-core.feature:46`; 1 insertion, 0 deletions
- [x] `git status --porcelain web/` prints nothing

Plan I finished 2026-09-02T15:17:53Z — commits `64b37e6`, `e6e43b3`, `724d202`.

### Plan II

- [x] `mix test test/whn/pipeline_test.exs` exits 0 — 6 tests, 0 failures; FC-01 (`{:segment_ready, 2, _}` then `{:last_frame, _}`, no error) and FC-04 (all segments delivered, no error, no frame message) sensed
- [x] `mix test test/whn/frames_test.exs` exits 0 — 3 tests, 0 failures; FC-06 sensed by the overhang fixture test (red first on `-0.25`, green with the `-1` retry)
- [x] Full `mix test` exits 0 — 48 tests, 0 failures, three consecutive runs with zero `[error]` logs; integration flows the real `{:last_frame, url}` into the wave-I head, and `drain_tasks` now genuinely absorbs the extraction tail (see task III deviation)
- [x] `mix compile --warnings-as-errors` exits 0; `mix precommit` clean
- [x] No diff to `server/test/support/pipeline_stub.ex` and nothing under `web/` across all three commits; `git status --porcelain web/` empty
- [x] Greps: `chain_frame` at `pipeline.ex:57` (run_cycle), `:79` (run_opening), helper `:147-157`; `next_frame(2, url) → {:ok, url}` at `:136`; `"-1"` retry at `frames.ex:51`; `fail_on_call` defined `fal_mock.ex:37` and armed `pipeline_test.exs:135`

Plan II finished 2026-09-02T15:35:00Z — commits `ff245af`, `b3d5c74`, `ea49cae`.

## PR

none yet

## Finished

## Nyquist results

Validated 2026-09-02 by jira-nyquist against commits `64b37e6..ea49cae` (plus one added test, `e1fc753`). Implementation untouched.

- [x] Pipeline emits the scene-end frame after the final segment, no error (FC-01) — command: `server/test/whn/pipeline_test.exs` "cycle emits the scene-end frame after the final segment, no error" (existing)
- [x] Opening chains its scene-end frame too — run_opening's chain_frame call site was grep-audited only (FC-01, opening path) — command: `server/test/whn/pipeline_test.exs` "opening emits its scene-end frame so the first cycle's bridge can chain" (added in commit e1fc753)
- [x] Stored frame seeds the next cycle's start_cycle ctx (FC-02) — command: `server/test/whn/episode_server_test.exs` "stored scene-end frame rides into the next cycle's ctx" (existing)
- [x] Frame intake exempt from the stale-beat guard, latest write wins (FC-03) — command: `server/test/whn/episode_server_test.exs` "frame intake is exempt from the stale-beat guard" (existing); source-audit: head at `episode_server.ex:122` above beat-guard head at `:126`
- [x] Failed trailing extraction: all segments delivered, no error, no frame message (FC-04) — command: `server/test/whn/pipeline_test.exs` "a failed scene-end extraction sends no frame message and no error" (existing)
- [x] Frame arriving during a zero-viewer hold refreshes the parked cycle at dispatch (FC-05) — command: `server/test/whn/episode_server_test.exs` "frame arriving during a zero-viewer hold refreshes the parked cycle at dispatch" (existing)
- [x] Audio overhang retried with -sseof -1 (FC-06) — command: `server/test/whn/frames_test.exs` "extracts a frame when the audio track outlasts the video stream" (existing); source-audit: retry at `frames.ex:51`; second failure propagates via the unreadable-video test
- [x] vote_closed waits for the scheduled reveal window (REV-01) — command: `server/test/whn/episode_server_test.exs` EP-05 test refute-then-drive (existing); source-audit: `reveal_ms: 2_500` at `episode_server.ex:32`, schedule site `:225`
- [x] Stale :vote_close falls through; open poll untouched (REV-02) — command: `server/test/whn/episode_server_test.exs` "a stale vote_close falls through" (existing); source-audit: guarded head `:198`, fall-through `:203`
- [x] Below quorum closes immediately, no vote_locked, revote re-offers, no generation (REV-03) — command: existing below-quorum/revote/zero-presence tests, byte-unmodified this sprint (diff-audited: only the planned EP-05 assertion swap removed a line from this file)
- [x] Full suite exits 0 — command: `mix test` — 49 tests, 0 failures; sole log line is FC-04's designed best-effort warning
- [x] `mix compile --warnings-as-errors` exits 0 — command
- [x] web/ untouched — artifact: `git status --porcelain web/` empty; `git log 64b37e6^..e1fc753 -- web/` empty
- [x] `server/test/support/pipeline_stub.ex` untouched — artifact: empty diff across sprint commits
- [x] EP-08 supersession is exactly one comment line — artifact: `git diff --numstat` on `episode-core.feature` = 1 insertion, 0 deletions; comment references @req:REV-03
- [x] CEL-04/05/06 and prior-sprint EP-* tests byte-unmodified — source-audit: only removed lines across sprint diffs are the planned EP-05 assertion and the deviation-logged `start_supervised!`/`start_link` → unlinked `start` swaps in test setups

Test suite: 49 passed / 49 total
