# Research: codebase — 2026-09-02-frame-chained-continuity

## Summary

- `state.last_frame_url` is written exactly once — `nil` at init (`server/lib/whn/episode_server.ex:69`) — and read exactly once, into every pipeline ctx (`episode_server.ex:418`). The bridge→scene half of the chain already works (`server/lib/whn/pipeline.ex:47-48`); the missing half is one extraction (`pipeline.ex:127` deliberately returns `{:ok, nil}` for segment 2) plus one new `{:pipeline, beat, {:last_frame, url}}` handler in the server.
- Timing works out under nominal spike numbers: final segment lands ~scene start +11-14s, extraction ~3s more, lock (and the beat bump that would stale the message) at scene start +20s — ~3-6s margin. A retried segment 2 (16s timeout + retry) blows past lock; the existing stale-beat guard (`episode_server.ex:122`) then drops the frame silently and the bridge falls back to t2v (`pipeline.ex:86-96`) — which is the correct degradation, because a frame arriving post-lock can no longer seed the already-dispatched cycle.
- Winner reveal: `vote_locked` and `vote_closed` broadcast on consecutive lines (`episode_server.ex:203-204`). The below-quorum branch broadcasts `vote_closed` with no preceding `vote_locked` (`episode_server.ex:176`) — nothing to reveal there, and its state reset (`vote: nil`, `:178`) makes a delayed close hazardous (gap votes would reply `:no_open_vote`, not `:locked`). Client needs no change: winner styling already renders on `vote.locked` (`web/src/components/vote-overlay.tsx:47,73`) and teardown is driven solely by `vote_closed` (`web/src/lib/useEpisode.ts:66`).
- Exactly one existing test breaks per change: `episode_server_test.exs:61` (asserts `vote_closed` within `assert_receive`'s 100ms default right after lock). No test asserts an exhaustive pipeline-message set, so `{:last_frame, url}` is additive for `pipeline_test`/`integration_test`.
- EP-08's feature text ("the pipeline impl is not invoked and the episode holds", `.jira/sprints/2026-08-31-live-episode-mvp/features/episode-core.feature:46-50`) no longer matches: with the quorum guard (`min_voters` ≥2, `episode_server.ex:74,171`), a zero-vote lock closes-and-revotes without holding (`episode_server.ex:174-179`; test retitled at `episode_server_test.exs:187-202`); "holds" now only describes the quorum-met-but-zero-viewers case (`episode_server.ex:216-222`, test `:204-227`).

## Findings

### 1. Frame chaining — `last_frame_url` end to end

**Server side (`server/lib/whn/episode_server.ex`):**

- Init sets `last_frame_url: nil` (`:69`); no other assignment exists (`grep -rn last_frame_url server/lib` → only `:69` and `:418`).
- `pipeline_ctx/2` (`:411-421`) reads `state.last_frame_url` into the ctx for **both** `dispatch(:start_opening, ...)` (`:130`) and `dispatch(:start_cycle, ...)` (`:139`, `:217`).
- Beat bump happens **at lock**: `lock_and_start_cycle` sets `beat: state.beat + 1` (`:210`) *before* building the ctx (`:214`). So a scene-end frame extracted during beat N playback must be in state before the `:vote_lock` handler runs.
- Stale-beat guard: `handle_info({:pipeline, beat, message}, %{beat: beat} = state)` (`:118-120`); any other beat is dropped without logging (`:122`). A `{:last_frame, url}` tagged with beat N arriving after lock (state.beat now N+1) is silently discarded.
- Below-quorum lock does **not** bump the beat (`:174-179` — state keeps `beat`), so a frame message still passes the guard during hold/revote for the same beat, and a later quorum lock consumes it — chaining survives revotes for free.
- Pipeline error handler (`:265-268`): `{:error, :frame, reason}` logs, and sets `"hold"` only if `playback == nil`. Relevant because the scene-end extraction failure would arrive via the same `{:error, stage, reason}` shape (see pipeline notes).

**Pipeline side (`server/lib/whn/pipeline.ex`):**

- The bridge→scene half already exists: `run_cycle` extracts the bridge's last frame and seeds the segments with it (`:46-48`); `run_opening` seeds segments from the flux still (`:62-69`). Both call the shared `run_segments/5` (`:48`, `:69`) — a single extraction hook there covers opening and cycle.
- The scene→bridge half is missing at exactly `next_frame(2, _url) → {:ok, nil}` (`:127`, comment "the last segment seeds nothing; skip the extraction round trip"). `next_frame/2` has neither `dest` nor `beat` in scope; `run_segments` has both (`:102`) and the segment `url` for idx 2 in scope (`:106-108`). Two observed insertion shapes (no recommendation): (a) special-case idx 2 inside the reduce — extract, `notify(dest, beat, {:last_frame, url})`, still return `{:ok, nil}`; (b) have `run_segments` return the final url and let `run_cycle`/`run_opening` extract+notify after the loop.
- Notification already precedes extraction in the loop (`:108` notify, then `:109` next_frame), so playback of segment 2 starts before any new extraction runs — the ~3s cost is off the delivery path by construction. `Task.Supervisor.start_child` (`:29`, `:34`) keeps the whole cycle off the EpisodeServer process.
- Failure semantics to decide: `extract_frame` wraps `with_retry(:frame, 9_000, ...)` (`:130-132`, timeout at `:25`); inside the reduce a failure `{:halt, {:error, :frame, reason}}` (`:112-113`) flows to `report/3` (`:134-138`) → `{:pipeline, beat, {:error, :frame, reason}}` — even though all three segments were already delivered. Whether a scene-end extraction failure should surface as a pipeline error (today's `:error` handler semantics, `episode_server.ex:265-268`) or be swallowed to nil is a planner call.
- `Whn.Frames.last_frame/1` (`server/lib/whn/frames.ex:16-31`): Req download → ffmpeg `-sseof -0.25` → `Whn.Fal.upload`; accepts local paths (`frames.ex:34-35`), which is what keeps the mocked pipeline tests running it for real.

**Timing model (spike-measured, `.jira/sprints/2026-08-31-live-episode-mvp/fal-spike.log:3-11`: flux 12.1s, i2v 4.9s, last_frame 2.9s, t2v 5.3s; timeouts are 3x at `pipeline.ex:22-25`):**

Let T = lock of vote N−1 = scene N−1 start +20s (vote opens at +10s per `vote_open_ms`, locks +10s later — `episode_server.ex:26-32,164,302`).

- Cycle N dispatched at T. Nominal: celeris ~2-5s → bridge i2v ready ~T+7-10s → frame ~3s → seg0 ~T+15-18s → frame → seg1 ~T+23-26s → frame → seg2 ready ~T+31-34s.
- Playback: scene N−1 boundary at T+10s pops the bridge (`advance/1`, `:292-305`); bridge plays T+10..T+20; scene N promotes at T+20 with whatever segments arrived (seg0 only, nominally). `vote_open` for beat N scheduled at scene-N promotion +10s → T+30 (`:302`); `vote_lock` at T+40 (`:164`).
- New extraction after seg2: done ~T+34-37 → `{:last_frame, url}` tagged beat N arrives while `state.beat == N` (lock at T+40) → guard passes, state written ~3-6s before the ctx is built. Matches the brief's "final segment ready ≈ scene start +8-15s vs lock at +20s, extraction ~3s".
- Degraded: one seg2 retry (16s video timeout + ~5s retry, `pipeline.ex:24,147-158`) pushes extraction past T+40 → beat bumped → message dropped at `episode_server.ex:122` → cycle N+1 already dispatched with `last_frame_url: nil` → t2v bridge (`pipeline.ex:86-96`). Dropping is *correct* here: accepting the late frame (e.g. guard on `beat == state.beat - 1`) could only seed cycle N+2 with a frame from two scenes back. Tagging the message with beat N+1 instead inverts the race (dropped whenever extraction finishes *before* lock, i.e. the common case). Conclusion from the code: tag with the current beat (ctx.beat) and accept the nominal-case guard as-is; the t2v branch is the designed fallback.
- Stale-frame residue: `last_frame_url` is never cleared. If scene N+1's extraction fails, the ctx at lock N+1→N+2 reuses scene N's frame (~40s stale, one scene behind). Consuming-once (nil it in `lock_and_start_cycle` after `:214`) is the available counter-measure; whether staleness beats t2v fallback is a planner call.

**Pinned contract:** the previous sprint's message contract (`.jira/sprints/2026-08-31-live-episode-mvp/CONTEXT.md:63-75`) lists four `{:pipeline, beat, ...}` shapes; the brief allows exactly one addition shaped `{:pipeline, beat, {:last_frame, url}}`. The `:error` stage enum in that contract already includes `:frame` (`CONTEXT.md:74`), so extraction failures need no contract change.

### 2. Winner reveal delay

- `lock_and_start_cycle` broadcasts back-to-back: `vote_locked` at `episode_server.ex:203`, `vote_closed` at `:204`. The rest of the handler (persist `:205`, beat bump `:210`, dispatch/hold `:216-222`) is unaffected by moving the close.
- Scheduling machinery exists: `schedule(event, ms)` → `Process.send_after(self(), {:timeline, event}, ms)` (`:445`); timings are injectable via `Map.merge(@default_timings, attrs.timings)` (`:26-32,50`) so a new key (e.g. `vote_close_delay_ms: 2_500`) is test-drivable without sleeps (per `server/AGENTS.md:72-78`: no `Process.sleep`; sync with `:sys.get_state`). Existing event names — `:presence_check, :vote_open, :vote_lock, :revote, :scene_boundary` — leave `:vote_close` free.
- State between lock and delayed close is already safe: post-lock votes reply `{:error, :locked}` (`:314`); `join_sync` returns `vote: nil` for a locked vote (`:327-328`) — a viewer joining inside the reveal window simply never sees the poll; the next `vote_open` overwrites `state.vote` unconditionally (`:151-165`) but can't fire earlier than the next scene's +10s (≥ ~20s after lock), far beyond 2.5s. No re-entrancy guard strictly required for a broadcast-only close handler.
- Below-quorum branch (`:174-179`): broadcasts `vote_closed` **immediately** with no `vote_locked`, resets `vote: nil`/`votes: %{}` and schedules `:revote`. Evidence for keeping it immediate: (a) nothing to reveal — client winner styling requires `locked && winner_idx` (`vote-overlay.tsx:73`), which a quorum-fail never sets; (b) the state reset means a delayed close would leave the client poll interactive while the server replies `:no_open_vote` (`:313`) to gap votes; (c) three tests consume this immediate close (`episode_server_test.exs:105,122,146`). Delaying it would require also delaying the state reset or accepting the reply mismatch.
- Client — no change needed, confirmed: `useEpisode.ts:52-65` upgrades the vote in place on `vote_locked` (`locked: true`, `winner_idx`); `:66` nulls it only on `vote_closed`; `routes/index.tsx:22-27` mounts `VoteOverlay` only while `vote` is non-null; `vote-overlay.tsx:47` (`revealed = your_vote !== null || locked`), `:73-77` (`.winner` class on `locked && winner_idx === idx`); the gate at `:16-20` force-shows a locked vote (`if (vote.your_vote !== null || vote.locked) return true`) so even a lag-gated viewer sees the reveal. Wire types unchanged: `web/src/lib/types.ts:16-24` already carries `locked`/`winner_idx`.

### 3. EP-08 predicate (hygiene)

- Feature text: `.jira/sprints/2026-08-31-live-episode-mvp/features/episode-core.feature:46-50` — "Given an episode booted with no presence entries / When the opening or a generation cycle would start / Then the pipeline impl is not invoked and the episode holds".
- Implemented behavior (post-sprint commit `ba56bb2` "vote quorum guard and english-only script output"):
  - Quorum guard is primary: `min_voters` default 2 (`episode_server.ex:74`), checked at lock (`:171`); below quorum → close-without-winner + `:revote` schedule, **no hold, no beat bump, no `vote_locked`** (`:174-179`). Test: `episode_server_test.exs:187-202`, retitled "zero presence: pipeline is never invoked" with the comment "(quorum guard subsumes the old zero-presence hold at lock)" (`:187`).
  - "Holds" now only describes quorum-met-but-zero-viewers-at-lock: ctx parked in `pending_cycle`, phase `"hold"`, presence recheck (`episode_server.ex:216-222`, `:137-144`). Test: `episode_server_test.exs:204-227`.
  - Opening gate unchanged: zero viewers → reschedule presence_check, no dispatch (`:129-135`).
- Also stale: the moduledoc already documents the new behavior (`episode_server.ex:11-14`), so only the `.feature` text lags. Note: the file lives under the **previous sprint's** directory, not a repo-root `features/`; whether this sprint edits it in place or carries a copy into its own `features/` is an orchestration question.

### Test and mock inventory (what the two behavior changes touch)

Breaks:

- `server/test/whn/episode_server_test.exs:61` — `assert_receive %Broadcast{event: "vote_closed"}` immediately after lock; a 2.5s default delay exceeds `assert_receive`'s 100ms default. Fix shapes available in-file: inject `timings: %{...}` via `start_episode` attrs (merge at `episode_server.ex:50`) or drive `{:timeline, :vote_close}` manually like every other event (`:37`).

Unaffected (verified per assertion):

- `episode_server_test.exs:105,122,146` — `vote_closed` from the below-quorum branch; stays immediate if that branch is unchanged.
- `server/test/whn_web/channels/episode_channel_test.exs` — never asserts `vote_closed`; EP-04 (`:75-91`) locks then votes, exercising `check_vote`, not broadcasts.
- `server/test/whn/integration_test.exs:126-130` — asserts `vote_locked` only (5s window); `vote_closed` never asserted; the episode is torn down in `on_exit` (`:179-191`) and a pending `send_after` to a dead pid is inert. The 3× `preload` gates (`:136,205`) count `preload` broadcasts, which `{:last_frame, ...}` does not emit. `drain_tasks` (`:219-229`) runs before the FalMock `on_exit` stop (reverse registration order: mock registered first at `:48-49`), so the extra ~3s of extraction inside the cycle task is waited out, not raced.
- `server/test/whn/pipeline_test.exs` — CEL-04 order test (`:92-110`) uses selective `assert_receive` + refutes only `{:error, ...}` (`:109`); CEL-05 counts `i2v` calls == 4 (`:119`) — extraction is not i2v; CEL-06 counts i2v == 4 (`:181`) — same; opening test refutes only `bridge_ready` (`:148`). All additive; new assertions for `{:last_frame, url}` would be new lines, not rewrites.

Mock/stub surfaces:

- `Whn.PipelineStub` (`server/test/support/pipeline_stub.ex:1-28`) produces **no** pipeline messages by design (`:3-5`); episode_server tests hand-send `{:pipeline, beat, ...}` (`episode_server_test.exs:36,161,181`). The new message needs no stub change — tests send it directly.
- `Whn.FalMock` (`server/test/support/fal_mock.ex`): video ops return the local mp4 fixture so `Whn.Frames.last_frame/1` runs for real (`:6-8`, fixture path branch `frames.ex:34-35`); `upload` returns a unique `mock://frame-N.jpg` (`:56-60`). A fourth extraction per cycle just adds one real ffmpeg run + one `:upload` call; `fail_once(:i2v)`-style arming also covers `:upload` if a test wants to exercise extraction failure (`:31-33,62-72`).

### Store option: persisting the scene-end frame in beat meta

- `persist_beat` writes `meta: %{"seed" => seed + beat}` fire-and-forget per segment (`episode_server.ex:391-407`); `Store.upsert_beat` replaces `:meta` **wholesale** on conflict (`server/lib/whn/store.ex:23-30`), and `Beat.changeset` casts `:meta` (`server/lib/whn/schemas/beat.ex:19-21`). So the frame URL *could* ride in scene-beat meta (attrs must re-include the seed key each upsert). Nothing reads beat meta at runtime today; value is restart-recovery/debugging only, and backend-restart recovery is out of scope per the brief — option noted, not needed for the loop.

### Files that change vs reference-only

Change: `server/lib/whn/episode_server.ex` (new `{:last_frame, url}` handler + delayed close + timing key), `server/lib/whn/pipeline.ex` (final-segment extraction + notify), `server/test/whn/episode_server_test.exs` (`:61` + new coverage), `.jira/sprints/2026-08-31-live-episode-mvp/features/episode-core.feature:46-50` (EP-08 text; see placement question), likely `server/test/whn/pipeline_test.exs` (additive assertions).

Reference-only: `server/lib/whn/frames.ex`, `server/lib/whn/store.ex`, `server/lib/whn/schemas/beat.ex`, `server/test/support/{pipeline_stub,fal_mock}.ex`, `server/test/whn/integration_test.exs`, `server/test/whn_web/channels/episode_channel_test.exs`, all of `web/src/` (frozen protocol; no client change needed), `.jira/sprints/2026-08-31-live-episode-mvp/CONTEXT.md` (pinned contract, gains one message shape by amendment in the new sprint's docs — the old file itself is locked).

### Architectural Responsibility Map (seed)

| Capability (brief) | Tier today | Where |
|---|---|---|
| Scene-end frame snapshot | API/Backend (pipeline task) | `pipeline.ex:102-132`, `frames.ex` (missing only the idx-2 hook at `pipeline.ex:127`) |
| Carry frame into next cycle | API/Backend (EpisodeServer state) | `episode_server.ex:69,418` (missing the write handler) |
| Bridge i2v from carried frame | API/Backend | `pipeline.ex:98-100` (built, tested `pipeline_test.exs:93,114`, unreachable in prod) |
| Bridge frame seeds next scene | API/Backend | `pipeline.ex:47-48` (works today) |
| Winner reveal window | API/Backend timing only | `episode_server.ex:203-204,445` |
| Winner styling + poll teardown | Browser/Client (no change) | `vote-overlay.tsx:47,73`; `useEpisode.ts:52-66`; `routes/index.tsx:22-27` |
| Frame persistence (optional) | Database/Storage | `store.ex:23-30`, `schemas/beat.ex:19-21` |
| EP-08 predicate | Docs/spec | `features/episode-core.feature:46-50` vs `episode_server_test.exs:187-227` |

## Open questions

1. Scene-end extraction failure semantics: surface as the existing `{:pipeline, beat, {:error, :frame, reason}}` (today's handler may set `"hold"` if playback is nil, `episode_server.ex:265-268`) or swallow to a nil frame? All segments are already delivered when it can fail.
2. Consume-once vs sticky `last_frame_url`: nil it out when the ctx is built at lock (`episode_server.ex:214`), or accept a one-scene-stale frame when a later extraction fails?
3. Should the delayed `vote_closed` handler also nil `state.vote`, or leave the locked map for the next `vote_open` to overwrite (current behavior; `sync_vote` already hides locked votes at `:327-328`)?
4. EP-08 feature file placement: the only copy lives in the *previous* sprint's `features/` — edit in place or fork into this sprint's own `features/` dir?
5. `handle_timeline(:vote_close, ...)` firing after episode phase changes (e.g. hold entered at lock via `:216-222`): broadcast-only close is phase-independent, but confirm no ordering requirement vs the `phase "hold"` broadcast for the client (client handles them independently — `useEpisode.ts:42,66`).
6. Reveal duration 2.5s is from the brief; segment boundary math (`vote_open` at +10s of the *next* scene) leaves ≥ ~20s of headroom, so nothing in the codebase constrains it below ~10s.

## Sources

### Primary (HIGH confidence)

- `server/lib/whn/episode_server.ex` — read in full this session; all line cites current on branch `jira/2026-08-31-live-episode-mvp` (HEAD `d31f418`).
- `server/lib/whn/pipeline.ex`, `server/lib/whn/frames.ex`, `server/lib/whn/store.ex`, `server/lib/whn/schemas/beat.ex` — read in full.
- `server/test/whn/{episode_server_test,pipeline_test,integration_test}.exs`, `server/test/whn_web/channels/episode_channel_test.exs`, `server/test/support/{pipeline_stub,fal_mock}.ex` — read in full.
- `web/src/lib/{useEpisode.ts,types.ts}`, `web/src/components/vote-overlay.tsx`, `web/src/routes/index.tsx` — read in full.
- `.jira/sprints/2026-08-31-live-episode-mvp/CONTEXT.md` (pinned interfaces, D-06/D-14/D-15), `features/episode-core.feature` — read in full.
- `.jira/sprints/2026-08-31-live-episode-mvp/fal-spike.log:3-11` — measured stage timings (flux 12130ms, i2v 4940ms, last_frame 2946ms, t2v 5293ms).
- `server/AGENTS.md:72-78` — test synchronization rules (no `Process.sleep`; `:sys.get_state`).
- `git log` — `ba56bb2` (quorum guard), `d31f418` (client playhead gating) confirm the post-sprint changes the brief says must stay intact.

### Secondary (MEDIUM confidence)

- `.jira/sprints/2026-08-31-live-episode-mvp/VERIFICATION.md:145-151` — verifier findings #1/#2 (unreachable i2v bridge; invisible reveal); conclusions independently re-verified against current source above, but its own line cites predate `ba56bb2` and are shifted.
- Timing-model arithmetic (T+ offsets, 3-6s margin) — derived from primary spike numbers + primary code paths, but Celeris live latency is an estimate (~2-5s) from the prior sprint's smoke claim in EXECUTION.md, not a measured stage.

### Tertiary (LOW confidence)

- None.
