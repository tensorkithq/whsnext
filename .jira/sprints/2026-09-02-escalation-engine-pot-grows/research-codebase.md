# Research: codebase — 2026-09-02-escalation-engine-pot-grows

All line cites are current on branch `gen/speakless`, HEAD `cb99238` (exactly one commit ahead of `main`; working tree clean under `server/`). Files read in full this session.

## Summary

- The +1-on-canonized-lock hook is a single function: `lock_and_start_cycle/2` (`server/lib/whn/episode_server.ex:218-244`) — the only code path where a vote canonizes (it already bumps `beat` at `:231` before building the ctx at `:235`). The below-quorum branch (`:183-189`) and the `:revote` path (`:205-214`) never reach it, so "no bump on revote" falls out of clause structure, not a new guard.
- The ctx is built in one place, `pipeline_ctx/2` (`episode_server.ex:432-442`); adding `absurdity_level` there covers all three dispatch sites (`:138` opening, `:149` parked-cycle refresh, `:238` lock). The parked-cycle refresh patches only `last_frame_url` — a level snapshotted at lock is already post-bump, so no refresh needed there.
- The Celeris user prompt is one heredoc, `Whn.Prompts.user_prompt/1` (`server/lib/whn/prompts.ex:111-118`); `story_state` is serialized in via `Jason.encode!` (`:115`). Vote options are the model's `next_choices` (schema-pinned to exactly 3, `server/lib/whn/celeris.ex:132`, clamped at `:195-205`), stored by the server at `episode_server.ex:262` and turned into the poll at `:161-176` — "escalation-form choices" is purely a prompt-rules change plus whatever fragment context the user prompt carries.
- The sectioned video_prompt (Camera/Environment/Action/Dialogue) is **requested, not enforced**: the section order lives only in the system prompt (`prompts.ex:23`); the only mechanical constraint today is the dialogue guard (`clamp_dialogue/strip_dialogue`, `prompts.ex:49-105`) applied in `Celeris.finalize/1` (`celeris.ex:238-244`). "Constrained into Environment/Action" has no existing validator to extend — `finalize/1` is the natural injection/enforcement seam, exactly where the Style suffix is already appended mechanically (`celeris.ex:244`).
- The script engine already writes `story_state`: its `story_state_updates` are merged **updates-win** at `episode_server.ex:255-256` and persisted wholesale (`:397-408` → `server/lib/whn/store.ex:56-61`). A level mirrored into `story_state` is therefore clobber-able by the model unless the server re-asserts it after every merge — the strongest codebase fact bearing on the brief's open question.

## Findings

### 1. EpisodeServer state, lock vs revote (feeds: Codebase)

State is a plain map built in `init/1` (`episode_server.ex:53-77`): `beat`, `vote`, `votes`, `next_choices`, `story_state`, `history`, `last_frame_url`, `timings`, `min_voters`, `pending_cycle`, etc. `absurdity_level: 0` would be one more key here (seedable via attrs like `story_state` at `:68` and `min_voters` at `:75`).

Vote close paths, exhaustively:

- `handle_timeline(:vote_lock, %{vote: %{locked: false}} = state)` (`:180-190`): quorum check `map_size(state.votes) >= state.min_voters` at `:181`.
  - **Canonized**: `lock_and_start_cycle(vote, state)` (`:218-244`) — computes winner (`:219-222`, D-02 tie-break via `Enum.max_by` on tallies with index), broadcasts `vote_locked` (`:224`), schedules the reveal close (`:225`), persists (`:226`), then sets `locked: true`, `beat: state.beat + 1` (`:228-233`), builds ctx (`:235`), dispatches or parks as `pending_cycle` on zero viewers (`:237-243`). The `+1` on `absurdity_level` belongs in the `:228-233` state update, beside the beat bump — one line, and the ctx at `:235` picks it up automatically for both the dispatch and the parked-cycle cases.
  - **Below quorum**: `:183-189` — broadcasts `vote_closed`, schedules `:revote`, keeps `beat` unchanged, stashes the same options in `next_choices`. Never calls `lock_and_start_cycle`. Test-asserted invariant: `state.beat == 0` after a below-quorum lock (`server/test/whn/episode_server_test.exs:141`).
- `handle_timeline(:revote, ...)` (`:205-214`): re-runs `:vote_open` with the stashed options; no lock, no bump.
- `handle_timeline(:vote_close, ...)` (`:198-203`): reveal-window close, broadcast-only, no state beyond `vote: nil`.

So "monotonic, +1 per canonized lock only" is satisfiable by touching exactly one function, and the opening (beat 0) never passes through it — L0 is the init value.

### 2. Pipeline ctx (feeds: Codebase, Architectural Responsibility Map)

`pipeline_ctx/2` (`episode_server.ex:432-442`) is the single ctx constructor: `%{beat, seed, episode, story_state, winning_choice, last_frame_url, history}`. Dispatch sites:

- opening: `dispatch(:start_opening, pipeline_ctx(state, nil))` (`:138`)
- canonized lock: `:235-238`
- parked-cycle dispatch after a hold: `%{state.pending_cycle | last_frame_url: state.last_frame_url}` (`:149`) — a map-update on the snapshot; a new ctx key is carried automatically, and since the level bumps at lock (before the snapshot), it cannot go stale during a hold the way frames can.

The ctx shape is a **pinned cross-sprint contract**: D-01 in `.jira/sprints/2026-09-02-frame-chained-continuity/CONTEXT.md:18-34` restates it in full and calls it "binding on this and future sprints". Adding `absurdity_level` is a contract amendment the new sprint must record, same as `last_frame_url` was.

Consumers of ctx: `Whn.Pipeline.run_cycle/run_opening` (`server/lib/whn/pipeline.ex:43-81`) pass it to `Whn.Celeris.run(ctx)` (`pipeline.ex:84`), which feeds `Prompts.user_prompt(ctx)` (`celeris.ex:65,102`) and seeds the request with `ctx.seed + ctx.beat` (`celeris.ex:106`). The opening flux prompt is built from ctx too (`pipeline.ex:90-92`) — an L0 Environment fragment could reach the opening still there.

### 3. Script-engine prompt construction and the sectioned video_prompt (feeds: Codebase, Patterns seed)

**User prompt** — `Prompts.user_prompt/1` (`prompts.ex:111-118`):

```
EPISODE: title — premise
BEAT: n
STORY STATE: <Jason.encode!(ctx.story_state)>
STORY SO FAR (oldest first): ... (`:120-125`)
THE AUDIENCE LOCKED: choice | OPENING — ... (`:127-128`)
```

A ladder fragment line (e.g. `ESCALATION (L2): the pot stands chest-high; ...`) slots in as one more interpolated line, keyed off a new `ctx.absurdity_level`. The **system prompt** (`prompts.ex:12-30`) is a single module attribute; the rules that would change for escalation-form choices are the `next_choices` rule (`:27`) and CONTINUITY (`:28`).

**Vote options provenance**: model `next_choices` → strict schema `minItems: 3, maxItems: 3` (`celeris.ex:132`) → `choices/1` clamp: 120 chars each, backfilled from `@fallback_choices` (`celeris.ex:195-205`, fallbacks at `:23-27`) → server stores at `episode_server.ex:262` → `handle_timeline(:vote_open, %{next_choices: [_|_]})` builds the poll (`:161-176`). Note the generic `@fallback_choices` ("Face the problem head-on"...) are **not** escalation-form — if the model fails twice, the fallback beat (`celeris.ex:215-236`) produces non-escalation options and prompts; the ladder fragment injected in `finalize/1` would still reach the fallback's video_prompts since `finalize` runs on the fallback too (`celeris.ex:44`).

**Sectioned video_prompt (commit cb99238)** — how it's built and constrained today:

- The Camera/Environment/Action/Dialogue section order is *requested* in one system-prompt rule (`prompts.ex:23`); `SPEAKLESS-ADHERENCE.md:99-111` documents the v9 "sectioned" format as shipped.
- The only mechanical enforcement is dialogue: `finalize/1` (`celeris.ex:238-244`) pipes `bridge.video_prompt` through `strip_dialogue` and `next_scene.video_prompt` through `clamp_dialogue`, then appends `"\nStyle: " <> vertical_suffix` (`:244`). `clamp_dialogue` (`prompts.ex:49-79`) caps to 12 words, forces the guard label `Dialogue (the only spoken words in the clip):` (`:42`, `ensure_guard` `:67-79`); `strip_dialogue` (`:87-92`) removes quotes and stray labels.
- **No code validates or parses Environment:/Action: sections.** `clip/1` only checks non-empty strings ≤1000 chars (`celeris.ex:179-190`). "Constrained into the Environment/Action sections" therefore needs new machinery; the two seams with precedent are `finalize/1` (mechanical, post-model, where Style is appended and dialogue is enforced — celeris.ex:238-244) and new `Prompts` helpers beside `clamp_dialogue` (the house pattern: "enforced mechanically, not just requested", `prompts.ex:38-39`).
- Caveat for injectors: `clamp_dialogue`'s `squeeze/1` (`prompts.ex:100-105`) collapses runs of 2+ whitespace to a single space across the **whole** prompt whenever a quoted line exists — an injected fragment's formatting must survive that (single `\n` survives; blank lines don't).
- Downstream, `run_segments/5` reuses `next_scene.video_prompt` for all three segments, stripping dialogue from segments 1-2 and appending `Continuation, part N of 3.` (`pipeline.ex:110-125`) — fragment prose injected into the scene prompt rides into every segment (quotes/label removed, everything else intact). The bridge prompt is a separate injection surface (`pipeline.ex:51`, t2v/i2v at `:94-107`).

### 4. Where a fixed L0–L5 ladder would live (feeds: Codebase, Patterns seed)

Existing homes for fixed creative text, in precedent order:

- **Module attributes**: `@system_prompt`/`@vertical_suffix` in `Whn.Prompts` (`prompts.ex:10-30`), `@fallback_choices` in `Whn.Celeris` (`celeris.ex:23-27`), `@default_timings` in `EpisodeServer` (`episode_server.ex:26-33`). A fixed L0-L5 list matches this exactly (e.g. in `Prompts`, indexed by level).
- **Seed attrs / story_state**: premise-specific content lives in `Whn.Seed.salary_just_entered/0` (`server/lib/whn/seed.ex:14-42`) — attrs flow `Whn.Episodes.start!/1` (`server/lib/whn/episodes.ex:11-19`) → `EpisodeServer.init` (`story_state` at `episode_server.ex:68`). The brief's "should not preclude premise-specific fragment sets" maps to this path: a `ladder` key riding episode attrs the way `story_state`/`seed` do. Nothing like it exists today; the current premise (Salary Just Entered, `seed.ex:14-42`) has no pot.
- **Config**: no precedent — `config :whn, :celeris` carries only url/key/req_options (`celeris.ex:76-79`; `server/config/*.exs` have no prompt/content config).

`priv/repo/seeds.exs:10-14` just calls `Whn.Seed` + `Store.create_episode`; note the DB row's `story_state` is only the *initial* state — `EpisodeServer` takes its live copy from attrs and overwrites the row as the model updates it (`store.ex:56-61`).

### 5. Test infrastructure (feeds: Patterns & conventions)

Binding rules: `server/AGENTS.md:69-78` — `start_supervised!`, no `Process.sleep`, sync via `:sys.get_state`. Hermetic env: `test/test_helper.exs:1-5` deletes `SCRIPT_ENGINE`/`VIDEO_ENGINE` (commit `cf79d87`).

- **EpisodeServer tests** (`test/whn/episode_server_test.exs`): `start_episode/1` helper with injectable attrs incl. `viewer_count_fn` (`:23-33`; `timings` mergeable via `episode_server.ex:51`); `open_vote/1` hand-sends `{:pipeline, 0, {:celeris, @celeris}}` + `{:timeline, :vote_open}` (`:35-39`) — tests drive every timeline event manually. `Whn.PipelineStub` records `{:start_cycle, ctx}` calls with the full ctx (`test/support/pipeline_stub.ex:19-27`), and tests already assert ctx fields after a lock (`ctx.winning_choice`, `ctx.beat` at `:68-70`; `ctx.last_frame_url` at `:270-271`) — "`absurdity_level` exposed to ctx, +1 on lock" asserts the same way.
  - **Extend for no-bump-on-revote**: "below quorum: poll closes without a winner and no generation starts" (`:126-143`, asserts `state.beat == 0` via `:sys.get_state` — add `absurdity_level == 0`) and "revote re-opens ... quorum then generates" (`:145-168` — assert the eventual ctx carries level 1, not 2).
- **Prompt assertions today**, two patterns:
  - Content of built prompts asserted directly on `Prompts.system_prompt()`/`user_prompt/1` returns (`test/whn/celeris_test.exs:148-164, 264-272`) and on `Celeris.run/1` results via a `Req.Test` stub of the chat endpoint (`:43-67`, `respond_with/1`).
  - **Emitted** prompts (what actually reaches the video model) captured from `Whn.FalMock.calls()` i2v/t2v/flux args (`test/whn/pipeline_test.exs:168-216, 231-240`; FalMock records `{fun, args}` — `test/support/fal_mock.ex:48-51`). "Ladder fragment present in the emitted prompt at each level" fits this pattern: run `start_cycle` with `ctx(%{absurdity_level: n})` (`pipeline_test.exs:93-109` ctx helper) and assert the fragment in the captured segment/bridge prompts. To assert the fragment reached the *Celeris request*, the `Req.Test` stub can inspect the request body as in `celeris_test.exs:84-111`.
- **FalMock** returns a real local mp4 so `Frames.last_frame/1` runs for real (`fal_mock.ex:3-9`); `fail_once/1` and `fail_on_call/2` (`:54-62`) exist for failure paths. Integration tests drive the full loop against Postgres with both mocks (`test/whn/integration_test.exs:82-91,109-158`).

### 6. story_state today (feeds: Codebase; bears on the open question)

- **Model → server**: `story_state_updates` is a free-form object in the strict schema (`celeris.ex:133`), passed through `updates/1` with no key filtering (`celeris.ex:207-208`).
- **Merge**: `handle_pipeline({:celeris, result}, state)` does `Map.merge(state.story_state, updates)` — **model updates win on key collision** (`episode_server.ex:255-256`).
- **Persist**: fire-and-forget task → `Store.update_story_state/2` replaces the episode row's map wholesale (`episode_server.ex:397-408`, `store.ex:56-61`).
- **Read**: only `Prompts.user_prompt/1` (`prompts.ex:115`); nothing else consumes it at runtime.

Implication for "mirror the level into story_state": a mirrored key is model-writable — one echoed `story_state_updates` containing that key silently overwrites the server's value at `:255-256`. Keeping the level server-side-only (ctx field + prompt line rendered from ctx, not from story_state) has no such hazard and needs no merge-guard code. If mirroring is chosen anyway, the merge at `:255-256` is the single place to re-assert the server value. The brief's own constraint ("never trusted to the script engine") points the same direction, but the choice is the planner's.

### Files that change vs reference-only (expected surface)

Change: `server/lib/whn/episode_server.ex` (state key, +1 in `lock_and_start_cycle`, ctx field), `server/lib/whn/prompts.ex` (ladder constants + user-prompt line + system-prompt rules for escalation-form choices; possibly an Environment/Action injection helper), `server/lib/whn/celeris.ex` (`finalize/1` if the fragment is mechanically constrained into the video_prompt; fallback prompts/choices if they must be escalation-aware), `server/test/whn/episode_server_test.exs`, `server/test/whn/celeris_test.exs`, `server/test/whn/pipeline_test.exs` (all additive per patterns above), plus the new sprint's ctx-contract amendment doc.

Reference-only: `server/lib/whn/pipeline.ex` (unless the bridge/segment prompts get separate fragment treatment), `server/lib/whn/seed.ex` + `priv/repo/seeds.exs` (premise seeding is #11, out of scope), `server/lib/whn/store.ex` + schemas (unless the level is persisted), `server/test/support/*` (stub/mock already sufficient), all of `web/` (options are opaque strings to the client; wire protocol untouched).

### Architectural Responsibility Map (seed)

| Capability (brief) | Tier today | Where |
|---|---|---|
| Own/bump `absurdity_level` | API/Backend (EpisodeServer state) | `episode_server.ex:53-77` (init), `:218-244` (lock; the only canonization path) |
| Expose level to pipeline ctx | API/Backend | `episode_server.ex:432-442` + pinned contract `frame-chained CONTEXT.md:18-34` |
| Ladder fragments (fixed text) | API/Backend module constants | precedent `prompts.ex:10-30`, `celeris.ex:23-27`; nothing exists yet |
| Inject into Celeris user prompt | API/Backend | `prompts.ex:111-118` |
| Constrain into video_prompt Env/Action | API/Backend (missing) | seam: `celeris.ex:238-244` (`finalize/1`); dialogue guard is the pattern (`prompts.ex:49-105`) |
| Escalation-form vote options | API/Backend (prompt rules) | `prompts.ex:27` (rule), `celeris.ex:132,195-205` (shape), `episode_server.ex:161-176,262` (flow) |
| No bump on revote | API/Backend | falls out of `episode_server.ex:183-189,205-214` never reaching `:218` |
| Level persistence (if any) | Database/Storage | `store.ex:56-61` (story_state, model-writable) or episode/beat schema (new column) |
| Options display | Browser/Client (no change) | opaque strings over `vote_open` |

## Open questions

1. Should the ladder fragment also shape the **bridge** video_prompt and the **opening flux still** (`pipeline.ex:51,90-92`), or only `next_scene`? The brief says "Environment/Action sections" (scene-shaped) but pixels persist via the bridge too.
2. `@fallback_choices` and the canned fallback beat (`celeris.ex:23-27,215-236`) are not escalation-form; after a double Celeris failure the vote would offer non-escalation options. In scope to make the fallback ladder-aware, or accepted degradation?
3. What does "constrained into the Environment/Action sections" mean mechanically when the model ignores the section format entirely (sections are requested-only)? Append-if-absent à la the Style suffix, or parse-and-rewrite à la `ensure_guard`? (External/patterns research may have the adherence data; codebase only shows the two seams.)
4. Does the level persist anywhere for restart recovery (episode row column, beat meta), or is in-memory + monotonic-from-attrs enough? Nothing reads persisted state at runtime today, and restart recovery has been out of scope in both prior sprints.
5. The pinned ctx contract (frame-chained D-01) needs a formal amendment for the new key — orchestration question for the new sprint's CONTEXT.md.

## Sources

### Primary (HIGH confidence)

- `server/lib/whn/episode_server.ex`, `server/lib/whn/celeris.ex`, `server/lib/whn/prompts.ex`, `server/lib/whn/pipeline.ex`, `server/lib/whn/store.ex`, `server/lib/whn/seed.ex`, `server/lib/whn/episodes.ex`, `server/lib/whn/schemas/{episode,beat}.ex`, `server/priv/repo/seeds.exs` — read in full this session at HEAD `cb99238`.
- `server/test/whn/{episode_server_test,celeris_test,pipeline_test}.exs`, `server/test/whn/integration_test.exs` (lines 40-160), `server/test/support/{pipeline_stub,fal_mock}.ex`, `server/test/test_helper.exs` — read this session.
- `.jira/STATE.md` (binding decisions D-01..D-16 + frame-chaining decisions), `.jira/sprints/2026-09-02-frame-chained-continuity/CONTEXT.md` (pinned ctx contract D-01, locked) — read in full.
- `SPEAKLESS-ADHERENCE.md` — the sectioned-prompt experiment behind cb99238; documents that sections are a format the *script engine* authors, with only the Dialogue block mechanically guaranteed.
- `PLOT.md` §5 (lines 97-121) — the three choice conditions the brief cites.
- `server/AGENTS.md:69-78` — binding test rules.
- `git log` — `gen/speakless` = `main` + `cb99238` only; `cf79d87` (env hermeticity) on main.

### Secondary (MEDIUM confidence)

- `.jira/sprints/2026-09-02-frame-chained-continuity/research-codebase.md` — prior sprint's map; its line numbers predate `cb99238`/`cf79d87` and are shifted; every claim reused above was re-verified against current source.

### Tertiary (LOW confidence)

- None.
