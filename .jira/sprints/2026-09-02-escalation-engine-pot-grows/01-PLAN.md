---
sprint: 2026-09-02-escalation-engine-pot-grows
plan: I
wave: I
goal: EpisodeServer owns absurdity_level (init 0, +1 per canonized lock only, clobber-proof) exposed via the pipeline ctx; L0–L5 ladder fragments render as an ESCALATION line in the Celeris user prompt and a mechanical Escalation append on every outgoing video prompt (scene, bridge, fallback, segments, opening still); vote options are escalation-form per system-prompt rules with a mechanical dedup — proven by all 11 EL- predicates sensed and mix test exiting 0.
worktree: false  # waves are strictly sequential on one shared branch; one executor at a time, so isolation buys nothing
branch: jira/2026-09-02-escalation-engine-pot-grows
issue: 8
depends_on: []
parallel_with: []
files_modified:
  - server/lib/whn/episode_server.ex
  - server/test/whn/episode_server_test.exs
covers:
  - D-02
  - D-03
  - D-09
  - D-10
  - "GOAL: absurdity_level lives in EpisodeServer state, +1 at each canonized lock, exposed to the pipeline ctx"
  - "GOAL: below-quorum revotes do NOT bump the level"
  - "GOAL: hermetic tests — level bump on lock, no bump on revote"
  - "RESEARCH: copy the beat counter pattern (init beside :beat, +1 beside the beat bump in lock_and_start_cycle, expose via pipeline_ctx/2)"
  - "RESEARCH: keep the level out of story_state — the updates-win merge at episode_server.ex:255-256 is model-clobber-able"
  - "RESEARCH: parked-cycle refresh needs no change — level snapshotted at lock is post-bump"
effects:
  - EL-01
  - EL-02
  - EL-03
---

# Plan I: Server-owned absurdity level

**Sprint goal:** see frontmatter `goal:`.
**This plan delivers:** the level's ownership: state key, monotonic bump at the single canonization path, ctx exposure (the D-03 contract amendment), and the three ownership predicates. It lands first because Plan II makes `Prompts.user_prompt/1` strict-read `ctx.absurdity_level` — every real ctx must already carry the key or the integration suite crashes mid-wave-II.

**Environment:** run inside `nix develop` from the repo root; Postgres on 57432 up; tests via `mix test` from `/home/drew/kit/whn/server`. Branch off `gen/speakless` per D-01 (`git checkout -b jira/2026-09-02-escalation-engine-pot-grows gen/speakless`).

## Tasks

### I. Level state key, lock bump, ctx exposure

- **Files:** `server/lib/whn/episode_server.ex`
- **Read first:** `server/lib/whn/episode_server.ex` (whole file — `init/1` state map, `handle_timeline(:vote_lock, ...)` pair, `lock_and_start_cycle/2`, `pipeline_ctx/2`), `.jira/sprints/2026-09-02-escalation-engine-pot-grows/research-codebase.md` §1–2, `.jira/sprints/2026-09-02-escalation-engine-pot-grows/CONTEXT.md` (D-02, D-03, D-09)
- **Action:** Per D-02, copy the `beat` counter pattern exactly, three touches:
  1. In the `init/1` state map, directly under `beat: 0` (line 60): `absurdity_level: 0`. L0 is the init value — the opening never passes through a lock.
  2. In `lock_and_start_cycle/2`'s state update (the `state = %{state | vote: ..., beat: state.beat + 1, scene_urls: []}` block at lines 228–233), add beside the beat bump: `absurdity_level: state.absurdity_level + 1`. This is the ONLY canonization path — the below-quorum branch (lines 183–189) and `:revote` (205–214) never reach it, so "no bump on revote" falls out of clause structure. Per D-09 the counter has no ceiling; only the fragment lookup clamps (Plan II). Do NOT touch the below-quorum, `:revote`, or `:vote_close` clauses.
  3. In `pipeline_ctx/2` (lines 432–442), add `absurdity_level: state.absurdity_level` to the ctx map. Per D-03 this amends the pinned ctx contract; the parked-cycle refresh at line 149 needs no change (the level is snapshotted post-bump at lock; only `last_frame_url` can go stale during a hold). Do NOT write the level into `story_state` anywhere, and do not add any re-stamp at the merge (lines 255–256) — the level never enters that map (D-02).
- **Done when:** `grep -n "absurdity_level" server/lib/whn/episode_server.ex` shows exactly three sites: the init map, the `lock_and_start_cycle` bump, and `pipeline_ctx`; `mix test` exits 0 unchanged (the key is additive — nothing reads it yet).
- **Covers:** D-02, D-03, D-09, GOAL: level in state / +1 per canonized lock / exposed to ctx

### II. Ownership tests: bump on lock, no bump on revote, clobber-proof

- **Files:** `server/test/whn/episode_server_test.exs`
- **Read first:** `server/test/whn/episode_server_test.exs` (the `start_episode/1` and `open_vote/1` helpers at lines 23–39, the lock test asserting `ctx.winning_choice`/`ctx.beat` around lines 42–70, the below-quorum test at 126–143, the revote-then-quorum test at 145–168), `server/AGENTS.md:69-78`, `.jira/sprints/2026-09-02-escalation-engine-pot-grows/features/absurdity-level.feature`
- **Action:** Three additive assertions/tests, each carrying its predicate-id comment (house style `# EL-01` above the test or assertion, per frame-chained D-07 convention):
  1. **EL-01:** in the existing quorum-lock test that already asserts ctx fields after `PipelineStub.calls()` (lines ~68–70), add `assert ctx.absurdity_level == 1` and `assert :sys.get_state(pid).absurdity_level == 1`.
  2. **EL-02:** in the below-quorum test (126–143), beside the existing `state.beat == 0` assertion (line ~141), add `assert state.absurdity_level == 0`. In the revote-then-quorum test (145–168), assert the eventually dispatched `{:start_cycle, ctx}` carries `ctx.absurdity_level == 1` — one lock happened, not two.
  3. **EL-03:** new test "script engine cannot clobber the level": `start_episode()`, then `send(pid, {:pipeline, 0, {:celeris, Map.put(@celeris, :story_state_updates, %{"absurdity_level" => 99})}})`, `send(pid, {:timeline, :vote_open})`, two distinct votes (quorum), `send(pid, {:timeline, :vote_lock})`, `:sys.get_state(pid)`; assert the dispatched ctx has `absurdity_level == 1` (server-owned, not 99 or 100) and `:sys.get_state(pid).absurdity_level == 1`. (The merged `story_state` will contain the model's key — that is allowed and unread; only the ctx field is the level.)
- **Done when:** `grep -n "EL-0" server/test/whn/episode_server_test.exs` shows EL-01, EL-02, EL-03 comments; `mix test test/whn/episode_server_test.exs` exits 0; full `mix test` exits 0.
- **Covers:** EL-01, EL-02, EL-03, GOAL: hermetic tests — bump on lock, no bump on revote

## Nyquist criteria for this plan

- [ ] `mix test test/whn/episode_server_test.exs` exits 0 with the EL-01/EL-02/EL-03 assertions present (EL-01, EL-02, EL-03)
- [ ] Full `mix test` exits 0 — the ctx key is purely additive before Plan II lands
- [ ] `grep -n "absurdity_level" server/lib/whn/episode_server.ex` — exactly the three ownership sites, none inside `handle_pipeline({:celeris, ...})` or the story_state merge (EL-03, D-02)
- [ ] `git status --porcelain web/` prints nothing

## Risks accepted in this plan

- Nothing consumes `ctx.absurdity_level` until Plan II — by design; the strict-read contract (D-03) activates in wave II.
- The raw counter is unbounded (D-09): lock 6+ produces levels above the ladder; the fragment clamp is Plan II's job, finale semantics are issue #9's.
- The merged `story_state` may carry a model-written `"absurdity_level"` key; it is unread by design (D-02) — no key filtering added.
- Level is in-memory only; a server restart resets it with the rest of episode state (D-10, third sprint running).
