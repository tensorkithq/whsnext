---
sprint: 2026-09-02-frame-chained-continuity
verified_at: 2026-09-02T15:45:00Z
verdict: PASS
---

# Verification: 2026-09-02-frame-chained-continuity

Goal-backward audit of the executed sprint. Asks: "does the codebase, as it stands now, deliver what the goal promised?" — distinct from `jira-nyquist` (which asks "do tests cover the criteria?") and `jira-reviewer` (which audits the diff).

## Goal

Scene-end frames chain each cycle into the next (pipeline emits `{:last_frame, url}`; server stores it latest-wins and seeds the next bridge ctx), `vote_closed` waits a scheduled 2.5s reveal after `vote_locked`, and the stale EP-08 predicate is superseded — proven by the server suite passing with all nine FC-/REV- predicates sensed and zero `web/` changes.

## Goal decomposition

- [x] 1. Every scene's final frame is snapshotted after the final segment is delivered (producer side, both `run_cycle` and `run_opening`), off the playback-critical path
- [x] 2. The snapshot survives extraction hazards: audio-overhang retry (`-sseof -1`) and a best-effort failure path that never flips a playable episode to hold
- [x] 3. The server stores the frame latest-wins, exempt from the stale-beat guard
- [x] 4. A quorum lock (≥2 distinct voters) dispatches the next cycle with `ctx.last_frame_url`; the bridge generates i2v FROM that frame (t2v only on a true cold start, `last_frame_url: nil`)
- [x] 5. The bridge's final frame seeds the winning option's next scene (pre-existing hop, regression-free)
- [x] 6. Generation-buffer overlap preserved: cycle dispatches at lock while the scene plays; the trailing extraction runs after the final segment's notify
- [x] 7. A frame arriving during a zero-viewer hold refreshes the parked cycle at deferred dispatch
- [x] 8. The audience sees the winner: `vote_locked` broadcasts, `vote_closed` waits a scheduled 2.5s reveal window guarded on `locked: true`; below-quorum close stays immediate
- [x] 9. The web client needs no change: winner styling on locked, force-show gate, `vote_closed` teardown all pre-exist; zero `web/` changes in sprint commits
- [x] 10. The stale EP-08 predicate is superseded by REV-03 with exactly one comment line in the old feature file
- [x] 11. Prior-sprint behavior regression-free (full suite green, pinned `PipelineStub` untouched)

## Findings

### 1. Scene-end frame snapshotted after the final segment, off the delivery path

- **Status:** delivered
- **Evidence:** source-audit — `server/lib/whn/pipeline.ex:136` (`next_frame(2, url)` returns the final segment url instead of `nil`), `server/lib/whn/pipeline.ex:147-157` (`chain_frame/3` calls `Whn.Frames.last_frame/1` and notifies `{:last_frame, frame_url}`), call sites in `run_cycle` at `pipeline.ex:57` and `run_opening` at `pipeline.ex:79`, both after `run_segments` returns — so `notify(dest, beat, {:segment_ready, 2, url})` (`pipeline.ex:116`) always precedes the ~3s extraction. Moduledoc documents the trailing extraction at `pipeline.ex:11-13`.
- **Evidence:** command — `mix test` (nix develop, cwd `server/`): 49 tests, 0 failures. FC-01 tests exercise both paths behaviorally: `server/test/whn/pipeline_test.exs:133-147` asserts `{:last_frame, url}` arrives after all three `segment_ready` with no error (cycle); `pipeline_test.exs:219-232` asserts the same for the opening.

### 2. Extraction hazards: overhang retry and best-effort degradation

- **Status:** delivered
- **Evidence:** source-audit — `server/lib/whn/frames.ex:49-54`: `-sseof -0.25` primary, retry once with `-sseof -1` on non-zero ffmpeg exit, second result returned as-is. `pipeline.ex:143-157`: trailing extraction is a single attempt (direct `Whn.Frames.last_frame/1`, no `with_retry`); failure logs a warning and sends nothing — no `{:error, :frame, _}` path exists in `chain_frame`. Intra-segment extractions keep their retry via `extract_frame/1` at `pipeline.ex:139-141`.
- **Evidence:** command — FC-06 overhang test (`server/test/whn/frames_test.exs:65-92`, video 1s / audio 1.5s fixture, only the `-1` retry can land) and FC-04 (`server/test/whn/pipeline_test.exs:150-165`, `fail_on_call(:upload, 4)` arms the trailing extraction's upload; all three segments delivered, no error, no frame message) both pass in the suite run. The suite's sole warning line is FC-04's designed skip: `scene-end frame extraction failed for beat 1: :fal_flaked`.

### 3. Latest-wins intake, beat-guard-exempt

- **Status:** delivered
- **Evidence:** source-audit — `server/lib/whn/episode_server.ex:122-124`: dedicated `handle_info({:pipeline, _beat, {:last_frame, url}}, state)` head stores unconditionally; it sits ABOVE the beat-guard head at `episode_server.ex:126` (clause order is load-bearing — below it, a matching-beat message would crash in `handle_pipeline/2`, which has no `{:last_frame, _}` clause). `last_frame_url` stays sticky (never nil'd at lock — `lock_and_start_cycle/2` at `:218-244` does not touch it), per Claude's-discretion in CONTEXT.md.
- **Evidence:** command — FC-03 test `server/test/whn/episode_server_test.exs:275-281` (beat tag 41 stored while `state.beat == 0`) passes.

### 4. Quorum lock seeds the next bridge from the scene-end frame; t2v only on cold start

- **Status:** delivered
- **Evidence:** source-audit — quorum: `episode_server.ex:180-190` (`map_size(state.votes) >= state.min_voters`, default 2 at `:75`); ctx carries the frame: `pipeline_ctx/2` at `episode_server.ex:439` (`last_frame_url: state.last_frame_url`); bridge dispatch on i2v vs t2v: `pipeline.ex:94-104` (`bridge_clip(%{last_frame_url: nil}, ...)` → `Whn.Fal.t2v`) vs `pipeline.ex:106-108` (`bridge_clip(%{last_frame_url: frame_url}, ...)` → `i2v(prompt, frame_url, seed)`).
- **Evidence:** command — FC-02 test `episode_server_test.exs:260-272` (stored frame rides into `start_cycle` ctx after a two-voter lock); CEL-05 `pipeline_test.exs:168-190` asserts the bridge i2v's image is the ctx frame (`bridge_image == "mock://prev.jpg"`); CEL-06 `pipeline_test.exs:235-256` asserts a nil `last_frame_url` routes the bridge through t2v. All pass.

### 5. Bridge frame seeds the next scene (pre-existing hop)

- **Status:** delivered
- **Evidence:** source-audit — `pipeline.ex:51-54`: `bridge_clip → notify bridge_ready → extract_frame(bridge_url) → run_segments(..., frame_url, ...)`; `run_segments` at `:110-123` chains segment N's extracted frame into segment N+1. Unchanged this sprint (`git diff fa1221e..HEAD` shows only the additive `chain_frame`/`next_frame` edits).
- **Evidence:** command — CEL-04/CEL-05 pass unmodified in the suite run (4 i2v calls: bridge + 3 chained segments).

### 6. Generation-buffer overlap preserved

- **Status:** delivered
- **Evidence:** source-audit — `episode_server.ex:237-238`: with viewers present, `dispatch(:start_cycle, ctx)` fires inside the lock handler while the current scene is still playing (playback queue at `:293-330` promotes bridge then scene independently) — overlap semantics untouched by this sprint. The new extraction cost sits after the final `segment_ready` notify by construction (`pipeline.ex:116` precedes `next_frame(2, url)` return; `chain_frame` runs after the whole segment loop).
- **Evidence:** command — FC-01 test asserts the message ORDER: all three `segment_ready` consumed before `{:last_frame, _}` arrives (`pipeline_test.exs:139-143`).

### 7. Deferred-cycle refresh at dispatch

- **Status:** delivered
- **Evidence:** source-audit — `episode_server.ex:145-154`: the `:presence_check` branch dispatches `%{state.pending_cycle | last_frame_url: state.last_frame_url}`, patching the lock-time snapshot with the latest frame.
- **Evidence:** command — FC-05 test `episode_server_test.exs:284-310` (frame sent during a zero-viewer hold; the dispatched ctx carries `"mock://held.jpg"` and the original `winning_choice`) passes.

### 8. Winner reveal window

- **Status:** delivered
- **Evidence:** source-audit — `episode_server.ex:32` (`reveal_ms: 2_500` in `@default_timings`), `:224-225` (`broadcast("vote_locked", ...)` then `schedule(:vote_close, state.timings.reveal_ms)` — no inline close on the quorum path), `:198-201` (guarded `handle_timeline(:vote_close, %{vote: %{locked: true}} = state)` broadcasts `vote_closed` and nils the vote), `:203` (silent fall-through), `:186` (below-quorum branch keeps its immediate `vote_closed` — exactly two `vote_closed` broadcast sites in the module).
- **Evidence:** command — REV-01 (`episode_server_test.exs:60-73`: `refute_receive vote_closed` after lock, then drive `:vote_close` and receive it) and REV-02 (`:77-99`: duplicate close silent; a reopened poll survives a straggling close, `vote.locked == false`) pass; REV-03 below-quorum/revote/zero-presence tests (`:126-143`, `:145-168`, `:218-232`) pass byte-unmodified this sprint (diff-audited: the only removed line in this file across sprint commits is the planned EP-05 inline-close assertion).

### 9. Web client unchanged and sufficient

- **Status:** delivered
- **Evidence:** command — `git log fa1221e..HEAD --oneline -- web/` is empty and `git status --porcelain` shows nothing under `web/` (sprint code diff touches only `server/` plus one feature-file comment line).
- **Evidence:** source-audit — the client already renders the reveal when given time: `web/src/lib/useEpisode.ts:53-66` (`vote_locked` sets `locked: true, winner_idx`; `vote_closed` → `setVote(null)`); `web/src/components/vote-overlay.tsx:17` (force-show gate returns true when `vote.locked`), `:47` (`revealed`), `:73-77` (winner bar styling `winner ? " winner" : ""` on `vote.locked && vote.winner_idx === idx`).

### 10. EP-08 superseded

- **Status:** delivered
- **Evidence:** artifact — `.jira/sprints/2026-08-31-live-episode-mvp/features/episode-core.feature:46`: one comment line above the `@req:EP-08` tag pointing to `@req:REV-03`; `git diff --numstat fa1221e..HEAD` on that file = 1 insertion, 0 deletions (scenario body byte-identical). The superseding predicate lives at `.jira/sprints/2026-09-02-frame-chained-continuity/features/winner-reveal.feature:16-22` (`@req:REV-03`, fresh id series per D-07).

### 11. Prior-sprint regression check

- **Status:** delivered
- **Evidence:** command — full `mix test` in nix develop (pg 57432 accepting connections): 49 tests, 0 failures; `mix precommit` (compile --warnings-as-errors, deps.unlock --unused, format, test — per `server/mix.exs:68`) exits clean.
- **Evidence:** source-audit — `git diff fa1221e..HEAD -- server/test/support/pipeline_stub.ex` is empty (pinned stub untouched). The one out-of-plan file, `server/test/whn/integration_test.exs`, changed only its mock setup (`FalMock.start_link` → unlinked `FalMock.start` + alive-guarded stop) — test infrastructure for the extraction tail outliving the test process (deviation logged in EXECUTION.md Plan II task III); no assertions changed.

## Source coverage

| Decision | Plan | Implemented | Evidence |
|----------|------|-------------|----------|
| D-01 (contract: `{:last_frame, url}` after final segment, at most once per cycle) | 02-PLAN.md task I | yes | source-audit: `pipeline.ex:57`, `:79`, `:147-157`, `:136`; notify precedes extraction |
| D-02 (latest-wins intake, beat-guard-exempt, clause order) | 01-PLAN.md task I | yes | source-audit: `episode_server.ex:122-124` above the guard pair at `:126-130` |
| D-03 (trailing extraction best-effort, never `{:error, :frame, _}`) | 02-PLAN.md tasks I+III | yes | source-audit: `pipeline.ex:143-157` (single attempt, warning log); command: FC-04 test |
| D-04 (`-sseof -0.25` primary, `-1` retry once, second failure as-is) | 02-PLAN.md task II | yes | source-audit: `frames.ex:49-54`; command: FC-06 + unreadable-video tests |
| D-05 (deferred-cycle ctx refresh at dispatch) | 01-PLAN.md task I | yes | source-audit: `episode_server.ex:145-154`; command: FC-05 test |
| D-06 (reveal_ms 2_500, scheduled `:vote_close`, guarded head + fall-through, below-quorum immediate) | 01-PLAN.md task II | yes | source-audit: `episode_server.ex:32`, `:186`, `:198-203`, `:225`; command: REV-01/REV-02 tests |
| D-07 (EP-08 supersession via one comment line; REV-03 fresh id) | 01-PLAN.md task III | yes | artifact: `episode-core.feature:46` (1 ins / 0 del); `winner-reveal.feature:16-22` |

Claude's-discretion items also verified in source: `FalMock.fail_on_call/2` additive (`fal_mock.ex:50-53`, checked in `dispatch/3` cond at `:92-101`; `fail_once/1` untouched at `:45-48`); sticky `last_frame_url` (no reset at lock); test fix drives `{:timeline, :vote_close}` manually with a prior `refute_receive` (`episode_server_test.exs:63-73`), no sleeps.

## Predicate coverage

| @req | Claimed by plan | Sensed | Evidence |
|------|-----------------|--------|----------|
| FC-01 | 02-PLAN.md | yes — suite run by verifier | command: `pipeline_test.exs:133-147` (cycle) and `:219-232` (opening), pass |
| FC-02 | 01-PLAN.md | yes — suite run by verifier | command: `episode_server_test.exs:260-272`, pass |
| FC-03 | 01-PLAN.md | yes — suite run by verifier | command: `episode_server_test.exs:275-281`, pass; source-audit: head order `:122` < `:126` |
| FC-04 | 02-PLAN.md | yes — suite run by verifier | command: `pipeline_test.exs:150-165`, pass |
| FC-05 | 01-PLAN.md | yes — suite run by verifier | command: `episode_server_test.exs:284-310`, pass |
| FC-06 | 02-PLAN.md | yes — suite run by verifier | command: `frames_test.exs:65-92`, pass |
| REV-01 | 01-PLAN.md | yes — suite run by verifier | command: `episode_server_test.exs:60-73` (refute + drive), pass |
| REV-02 | 01-PLAN.md | yes — suite run by verifier | command: `episode_server_test.exs:77-99`, pass |
| REV-03 | 01-PLAN.md | yes — suite run by verifier | command: below-quorum/revote/zero-presence tests, byte-unmodified this sprint, pass |

All nine predicates are claimed by a plan `effects:` and machine-sensed. No unclaimed and no unsensed predicates.

## Verdict

**PASS** — all 11 decomposed outcomes delivered; all 7 locked decisions implemented with source anchors; all 9 FC-/REV- predicates sensed by a suite run performed by the verifier (49/49, `mix precommit` clean); zero `web/` changes across sprint commits.

Caveat (does not affect the verdict, mirrors 02-PLAN.md accepted risk): the full frame chain is mock-verified only — live fal spend was not sanctioned for verification, so the end-to-end visual continuity of real H3 Max output rests on the hermetic suite plus the prior spike timings. A production smoke belongs outside this sprint.

## Next steps

None required for this sprint. Deferred items remain recorded in CONTEXT.md (frame-URL beat-meta persistence, monotonic beat check, `end_image_url` upgrade, production smoke of the live chain).
