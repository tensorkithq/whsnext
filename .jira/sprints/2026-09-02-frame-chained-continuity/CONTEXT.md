---
sprint: 2026-09-02-frame-chained-continuity
created: 2026-09-02
status: locked
---

# Context: 2026-09-02-frame-chained-continuity

Locked decisions for this sprint. The user confirmed the direction in the brief (2026-09-02); research resolved the design forks; the planner adopted the research recommendations as decisions below. Once written here, decisions are NON-NEGOTIABLE for downstream agents.

## Phase boundary

This sprint closes the frame-chaining loop on the live episode (scene-end frame extracted and carried into the next cycle's bridge), delays `vote_closed` so the winner highlight is visible, and supersedes the stale EP-08 predicate. All changes live in `server/` plus one comment line in the previous sprint's feature file. **Zero changes under `web/`** — the wire protocol is frozen and the client already renders the reveal when given time. Continues on branch `jira/2026-08-31-live-episode-mvp` (PR #6 collects it).

## Decisions

- **D-00 (goal restatement):** The sprint goal, measurable: scene-end frames chain each cycle into the next (pipeline emits `{:last_frame, url}` after the final segment; the server stores it latest-wins and the next `start_cycle` ctx carries it into the i2v bridge), the winner reveal holds `vote_closed` for a scheduled 2.5s window after `vote_locked`, and the stale EP-08 predicate is superseded — proven by the server test suite passing with all nine FC-/REV- predicates sensed, grep-visible code anchors, and an empty `git status` under `web/`. *(planner restatement; adds verification surface, reduces nothing)*
- **D-01 (pipeline message contract amendment):** The pinned contract from `2026-08-31-live-episode-mvp/CONTEXT.md` gains exactly one message. The updated contract, restated in full (binding on this and future sprints):

  ```elixir
  # ctx: %{beat, seed, episode: %{title, premise}, story_state, winning_choice (nil for opening),
  #        last_frame_url (nil for opening), history: [scene_summary, oldest first]}
  # messages sent to dest:
  #   {:pipeline, beat, {:celeris, result}}              # result per README §5, atom keys; bridge: nil for opening
  #   {:pipeline, beat, {:bridge_ready, url}}
  #   {:pipeline, beat, {:segment_ready, seg_idx, url}}  # seg_idx 0..2, in order
  #   {:pipeline, beat, {:last_frame, url}}              # NEW: scene-end frame, emitted at most once per
  #                                                      #   cycle, after {:segment_ready, 2, _}; beat tag =
  #                                                      #   producing cycle's ctx.beat (logging only — the
  #                                                      #   consumer is exempt from the stale-beat guard, D-02)
  #   {:pipeline, beat, {:error, stage, reason}}         # stage ∈ :celeris | :bridge | :frame | :segment
  ```

  Emission is hooked after the final segment's `notify` (shared by `run_cycle` and `run_opening` via `run_segments`), so the ~3s extraction cost sits after segment delivery, off the playback-critical path. All other pinned interfaces from the previous sprint remain binding unchanged. *(brief-locked shape; research-locked hook)*
- **D-02 (latest-wins intake):** The server consumes `{:last_frame, url}` in a dedicated `handle_info` head placed BEFORE the beat-guard pair in `episode_server.ex`, storing `last_frame_url` unconditionally — latest write wins, any beat tag accepted. Rationale: extraction can straddle the lock's beat bump; tagging ahead inverts the race, and the reference impl keeps the last frame as latest-ground-truth while per-beat artifacts stay guarded. Clause order is load-bearing: without this head, a matching-beat message falls into `handle_pipeline/2` and crashes the server. *(research Q1, option b)*
- **D-03 (trailing extraction is best-effort):** The scene-end extraction is a single attempt (no `with_retry`) that on success notifies `{:last_frame, url}` and on failure logs a warning and sends nothing. It must NEVER flow through `{:pipeline, beat, {:error, :frame, _}}` — all three segments are already delivered when it can fail, and an error would flip a playable episode to hold. Degradation path: next bridge falls back to t2v exactly as today. Intra-segment extractions keep their existing retry (they are load-bearing). *(research pitfall; reference: "the previous frame is still the ground truth")*
- **D-04 (audio-overhang retry):** `Whn.Frames.extract/2` keeps `-sseof -0.25` as the primary recipe (spike-proven, byte-identical to the reference) and on a non-zero ffmpeg exit retries once with `-sseof -1` — the AAC track can outlast the video stream, and an overhang > ~0.25s seeks past the last video frame. Still inside the user's "last second of that frame" intent. Second failure returns the error as-is. *(research pitfall, empirically verified)*
- **D-05 (deferred-cycle refresh):** `pending_cycle` snapshots ctx at lock; a frame arriving during a zero-viewer hold would otherwise be silently unused. At the `:presence_check` dispatch of a parked cycle, patch `last_frame_url: state.last_frame_url` into the ctx before dispatching. *(research pitfall)*
- **D-06 (winner reveal):** New timing key `reveal_ms: 2_500` in `@default_timings`. The quorum-lock branch replaces the immediate `broadcast("vote_closed", %{})` with `schedule(:vote_close, state.timings.reveal_ms)`. New timeline clause `handle_timeline(:vote_close, %{vote: %{locked: true}} = state)` broadcasts `vote_closed` and sets `vote: nil` (mirrors the below-quorum cleanup; makes a duplicate close fall through), plus a silent fall-through clause — house guarded-head style. The below-quorum branch keeps its IMMEDIATE `vote_closed` untouched: no `vote_locked` precedes it, so there is nothing to reveal, and its synchronous `vote: nil` reset conflicts with a delay. No client change. *(brief + research Q2)*
- **D-07 (EP-08 supersession):** The corrected predicate lives in THIS sprint's `features/winner-reveal.feature` as `@req:REV-03` (fresh id series — FC-/REV-, not reused EP-). In the old file (`.jira/sprints/2026-08-31-live-episode-mvp/features/episode-core.feature`), add exactly one comment line above the EP-08 scenario pointing to REV-03; its tags, Given/When/Then, and every other scenario stay byte-identical. In-place rewrite would attribute post-sprint behavior to `@plan:IV` and desynchronize the frozen 33/33 verification claim map. *(research Q4)*

## Claude's discretion

- **`reveal_ms` = 2_500** exactly — product feel per the brief's "~2.5s"; timings-injectable so trivially tunable later.
- **Monotonic beat check on frame intake: skipped.** The only hazard is a zombie cycle (whose segments were already dropped as stale) overwriting a fresher frame — worst case one bridge seeds from a one-beat-old frame of visually adjacent content. Serial dispatch (one cycle per lock) makes it near-unreachable; not worth the state.
- **`last_frame_url` stays sticky (no consume-once nil at lock).** If a later extraction fails, the next bridge reuses the latest successfully extracted frame rather than falling to t2v — same character/setting beats a fresh unanchored generation; matches the reference's ground-truth semantics.
- **FalMock gains `fail_on_call(fun, n)`** (fail the Nth call to `fun`; additive, `fail_once/1` untouched). `fail_once(:upload)` cannot deterministically target the trailing extraction because the bridge and two intra-segment extractions upload first and their retries would absorb the armed failure.
- **Test fix for `episode_server_test.exs:61`:** drive `{:timeline, :vote_close}` manually (house style — tests drive every timeline event), asserting `vote_closed` is NOT received before the drive. No timing injection, no sleeps.
- **Beat-meta persistence of the frame URL: deferred** (below). Not a one-line addition — the URL doesn't exist yet when `persist_beat` runs at `segment_ready` time, so it would need a new upsert call and a meta-shape change; nothing reads beat meta at runtime and restart recovery is out of scope.

## Deferred ideas

- Persist the scene-end frame URL into scene-beat `meta` → future (restart-recovery/debug value only; recovery is out of scope per the brief)
- Monotonic beat check on `{:last_frame, _}` intake → future, only if zombie-cycle overwrites are ever observed
- `end_image_url` on H3 Max i2v ("bridge ends on the next scene's opening frame") → future upgrade, recorded in research-external.md
- Speculative branch generation, prod hardening, episode duration caps, comments/share, backend-restart recovery → out of scope per the brief
- Reworking the vote flow beyond the reveal delay → out of scope per the brief

## Canonical references

- `.jira/sprints/2026-08-31-live-episode-mvp/CONTEXT.md` — pinned interfaces (wire protocol, `Whn.Fal`, pipeline boundary, store, supervision names); all remain binding except the D-01 amendment above.
- `.jira/sprints/2026-09-02-frame-chained-continuity/research-codebase.md` — every path:line anchor executors need (read before touching anything).
- `.jira/sprints/2026-09-02-frame-chained-continuity/research-patterns.md` — clause-ordering idiom, guarded-head + fall-through precedents, reference-impl frame discipline.
- `server/AGENTS.md` — binding test rules: `start_supervised!`, no `Process.sleep`, sync with `:sys.get_state`.
- `.jira/sprints/2026-08-31-live-episode-mvp/fal-spike.log` — measured stage timings (i2v 4,940ms, last_frame 2,946ms) behind the 3–6s margin math.
- `web/src/lib/types.ts`, `web/src/lib/useEpisode.ts`, `web/src/components/vote-overlay.tsx` — frozen; read-only confirmation that the client renders the reveal unchanged.
- Executor environment: run inside `nix develop` from the repo root; Postgres on port 57432 must be up; tests via `mix test` from `server/`.
