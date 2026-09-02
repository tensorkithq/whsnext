# Research: patterns — 2026-09-02-escalation-engine-pot-grows

## Summary

- The `beat` counter is the exact template for `absurdity_level`: an integer in EpisodeServer state, bumped only inside `lock_and_start_cycle/2` (the single canonized-lock path), untouched by the below-quorum branch — tests already assert `state.beat == 0` after a failed quorum. Copying this placement gets "bump on lock, no bump on revote" almost for free.
- The repo's enforcement doctrine is explicit and repeated in comments: model output is untrusted; constraints are applied mechanically post-parse (`clamp_dialogue`, `strip_dialogue`, forced `duration: 30`, choice clamping), never merely requested in the prompt. The constraining hook for video_prompts is `Celeris.finalize/1` — but note: Environment/Action sections are today only *requested* (system prompt), never mechanically parsed or edited. Only Style (appended) and Dialogue (guard label) are mechanically guaranteed. The ladder injection would be the first mechanical touch of Environment/Action.
- Both adherence logs are empirical ground for server-owned state: WORDLESS proved "no wording is seed-proof — prompt format shifts the distribution; it does not close the tap," and that kitchen-sink clause stacking made adherence *worse*. SPEAKLESS proved sectioned prompts win on checkability, not adherence, and that prose-injection paths create join artifacts.
- Fixed data tables live as module attributes next to their consumer (`@default_timings`, `@vertical_suffix`, `@fallback_choices`, pipeline timeouts); premise-specific content lives in `Whn.Seed` attrs / `story_state`. A generic L0–L5 ladder fits the module-attribute pattern; premise-specific fragments fit the seed-attrs pattern (episode attrs flow into server state at `init`).
- Pitfall found: if `absurdity_level` is mirrored into `story_state`, the existing merge (`Map.merge(state.story_state, story_state_updates)`) lets the script engine overwrite it — model updates win the merge. Any mirror must be re-stamped after the merge or the merge must protect server-owned keys.

## Findings

### 1. Server-owned mechanical state in EpisodeServer (template for `absurdity_level`)

- State is a plain map built in `init/1`; `beat: 0` initialized at `server/lib/whn/episode_server.ex:60`. A new integer field is one line here.
- The **only** place `beat` increments is the canonized-lock path: `lock_and_start_cycle/2`, `beat: state.beat + 1` at `episode_server.ex:231`, after the `vote_locked` broadcast and `persist_finalize`. The below-quorum branch (`handle_timeline(:vote_lock, ...)` at `episode_server.ex:180-189`) closes the poll, schedules `:revote`, and never touches `beat` — the test asserts `state.beat == 0` after a below-quorum close (`server/test/whn/episode_server_test.exs:141`). This is exactly the monotonic +1-per-lock / never-on-revote semantics the issue demands.
- Guarded-head style for timeline safety: every timeline event has a guarded clause plus a silent fall-through (`:vote_lock` guarded on `locked: false` at `episode_server.ex:180`, fall-through at `:192`; `:vote_close` guarded on `locked: true` at `:198`, fall-through at `:203`). D-06 in the prior sprint's CONTEXT.md names this "house guarded-head style" (`.jira/sprints/2026-09-02-frame-chained-continuity/CONTEXT.md`).
- The **beat-guard-exempt head**: pipeline messages are stale-dropped by beat match (`episode_server.ex:126-130`), except `{:last_frame, url}`, which has a dedicated head placed BEFORE the guard pair, latest-write-wins, any beat tag (`episode_server.ex:120-124`; STATE.md frame-chaining decision; CONTEXT.md D-02 notes clause order is load-bearing — a matching-beat message falling into `handle_pipeline/2` would crash). Relevant only if the escalation engine ever consumes pipeline feedback; the level itself needs no exemption since it is bumped synchronously at lock, not via pipeline message.
- Exposure to the pipeline: `pipeline_ctx/2` at `episode_server.ex:432-442` builds the ctx map (`beat`, `seed`, `episode`, `story_state`, `winning_choice`, `last_frame_url`, `history`). Adding `absurdity_level` there is the established route. Note the parked-cycle refresh precedent: `pending_cycle` ctx is snapshotted at lock and `last_frame_url` is refreshed at dispatch (`episode_server.ex:145-153`). The level is bumped *before* the ctx snapshot in `lock_and_start_cycle` (`:228-235`), so a parked ctx already carries the right level — no refresh needed, but the precedent exists.
- Timings/transitions: all transitions are `{:timeline, event}` self-messages via `schedule/2` (`episode_server.ex:466`), timings merged from an injectable map over `@default_timings` (`episode_server.ex:26-33, :51`) — D-14. Tests drive every timeline event manually.

### 2. Prompt-construction conventions (post cb99238, on gen/speakless)

- Section order is pinned by the system prompt, one label per line: `Camera:` / `Environment:` / `Action:` / `Dialogue:` (`server/lib/whn/prompts.ex:23`), with `Style:` appended mechanically as the last section (`server/lib/whn/celeris.ex:244`, `suffix/1`: `video_prompt <> "\nStyle: " <> Prompts.vertical_suffix()`).
- **Enforced vs requested** — the repo's split, stated in comments:
  - Requested only: section structure, Environment/Action content, final-frame hygiene, choice quality — all system-prompt prose (`prompts.ex:12-30`). Nothing parses or validates Camera/Environment/Action today; `Celeris.clip/1` only checks non-empty strings and a 1,000-char cap (`celeris.ex:179-190`).
  - Enforced mechanically: dialogue cap ("Enforced mechanically, not just requested: the model's output is untrusted like every other field" — `prompts.ex:38-39`); `clamp_dialogue/1` keeps the first quoted span, truncates to 12 words, guarantees the guard label (`prompts.ex:49-79`); `strip_dialogue/1` for bridges and segments 2–3 (`prompts.ex:87-92`; applied per-segment at `server/lib/whn/pipeline.ex:112-115`); `next_scene.duration` forced to 30 (`celeris.ex:172`); choices clamped and padded (below).
  - The single constraining hook for outgoing video_prompts is `Celeris.finalize/1` (`celeris.ex:238-244`). "Constrained into the Environment/Action sections" has no existing mechanism — the closest precedents are (a) `ensure_guard/1`, which locates an insertion point by regex and injects a labeled block (`prompts.ex:67-79`), and (b) the plain-append `suffix/1`. SPEAKLESS finding 4 warns about the splice approach: the old marker-injection path produced a missing-space join artifact ("falls silent.then he says nothing more"); the sectioned rewrite "removes the injection path and the artifact with it" (`SPEAKLESS-ADHERENCE.md:94-97`).
  - Fallback prompts flow through `finalize/1` too — the canned fallback video_prompts (`celeris.ex:215-236`) are unsectioned prose; any ladder injection must handle them.
- User-prompt convention: UPPERCASE labeled lines (`EPISODE:`, `BEAT:`, `STORY STATE:`, `STORY SO FAR`, `THE AUDIENCE LOCKED:`) rendered from ctx in `Prompts.user_prompt/1` (`prompts.ex:111-128`). A ladder fragment injected into the script-engine prompt would follow this labeled-line style.
- Seeds: script call uses `ctx.seed + ctx.beat` (`celeris.ex:106`), pipeline the same sum (`pipeline.ex:45`) — per-beat determinism convention.
- **Branch caveat:** the sectioned format + guard label is exactly one commit ahead of main (`main..gen/speakless` = cb99238 only, touching `prompts.ex`, `celeris.ex`, `celeris_test.exs`, `SPEAKLESS-ADHERENCE.md`). On `main`, `clamp_dialogue` still injects silence-marker prose. The escalation sprint's base branch determines which constraining surface exists.

### 3. Config/constants — where a fragment ladder would live

- Fixed data tables are module attributes co-located with their consumer, not config: `@default_timings` (`episode_server.ex:26-33`), `@vote_question` (`:24`), `@vertical_suffix` / `@system_prompt` (`prompts.ex:10-30`), `@max_dialogue_words` / `@dialogue_guard` (`prompts.ex:40-42`), `@fallback_choices` (`celeris.ex:23-27`), stage timeouts (`pipeline.ex:29-31`).
- `config.exs` holds only infra (endpoint, logger, tesla adapter — `server/config/config.exs:10-38`); nothing content-shaped lives there.
- Premise-specific content lives in `Whn.Seed`: one function per episode returning an attrs map with `title`, `premise`, fixed `seed`, rich `story_state` (`server/lib/whn/seed.ex:14-42`, D-13). Episode attrs flow into server state at `init` (`episode_server.ex:53-77`), so a premise-specific ladder could ride the same attrs path (as `story_state` does at `:68`) without new machinery.
- Fit: a generic L0–L5 ladder matches the module-attribute pattern (like `@fallback_choices`); Amaka's-pot-specific fragments (issue #11, out of scope but "design should not preclude premise-specific fragment sets" per the brief) match the seed-attrs pattern. The two compose: attribute as default, attrs override — same shape as `timings` (`episode_server.ex:51`) and `min_voters` (`:75`).

### 4. Test conventions

- Hermeticity: `test_helper.exs` deletes `SCRIPT_ENGINE` and `VIDEO_ENGINE` before ExUnit boots because the devshell sources `.env` ("a test that needs one sets it explicitly and cleans up") — `server/test/test_helper.exs:1-8` (commits cf79d87, 61f36b3). Suites that swap global app env are `async: false` with save-previous/restore `on_exit` (`celeris_test.exs:3, 43-61`; `pipeline_test.exs:2, 45-67`).
- EpisodeServer tests drive everything manually: `send(pid, {:timeline, event})` and `send(pid, {:pipeline, beat, msg})`, with `:sys.get_state(pid)` as the sync barrier before asserting on stub calls or state (`episode_server_test.exs:35-39, 58-68`). No sleeps, no timing injection (prior sprint CONTEXT.md discretion: "house style — tests drive every timeline event").
- Mock injection: pipeline via `Application.put_env(:whn, :pipeline_impl, Whn.PipelineStub)` in setup (`episode_server_test.exs:16-17`; read at `episode_server.ex:451`); `Whn.PipelineStub` is a call-recording Agent (`server/test/support/pipeline_stub.ex`); fal via `:fal_impl` → `Whn.FalMock`, a behaviour-conforming Agent with `fail_once/1` / `fail_on_call/2` (`server/test/support/fal_mock.ex`); Celeris stubbed via `Req.Test` plug in the `:celeris` app config (`celeris_test.exs:47-50`).
- Existing lock/revote structure to extend for the three demanded assertions:
  - Bump on lock: the quorum-lock test asserts `ctx.beat == 1` in the dispatched `start_cycle` ctx (`episode_server_test.exs:68-70`) — the level assertion is the same shape.
  - No bump on revote: below-quorum test asserts `state.beat == 0`, `vote == nil`, options re-offered, no pipeline call (`episode_server_test.exs:126-143`); revote-then-quorum test re-locks and inspects ctx (`:145-168`).
  - Fragment in the emitted prompt: two precedents — `celeris_test.exs` asserts on `finalize/1` output strings (suffix presence `:166-172`, guard-label placement `:174-201`); `pipeline_test.exs` asserts on the actual prompt handed to `FalMock.i2v` (`pipeline_test.exs:183-189`, `:192-215`). "Ladder fragment present at each level" maps onto both layers.
- Naming: tests carry requirement-tag comments (`# EP-05`, `# FC-02`, `# REV-02`) linking to Gherkin scenarios in the sprint's `features/*.feature` with `@req:`/`@plan:`/`@wave:` tags (`episode_server_test.exs:41, 259, 274`; `.jira/sprints/2026-09-02-frame-chained-continuity/features/frame-chain.feature:4-38`). New sprints mint a fresh id series (CONTEXT.md D-07: "fresh id series — FC-/REV-, not reused EP-").
- Video-needing tests build a 1s mp4 fixture with ffmpeg in setup (`pipeline_test.exs:22-36`); FalMock is started unlinked when the cycle task outlives the test (`fal_mock.ex:21-28`, `pipeline_test.exs:38-43, 75-88`).

### 5. Adherence-log lessons (the design rationale)

- `SPEAKLESS-ADHERENCE.md` (repo root, gen/speakless only): 11 clips, 9 dialogue formats, all perfect fidelity/zero leakage — adherence saturated, so the sectioned format won on **structural checkability**, not adherence: "the spoken line lives in its own labeled block instead of being fished out of scene prose" (`SPEAKLESS-ADHERENCE.md:70-79`). Finding 3: saturation "is meaningful but not proof against regression on other scenarios — the mechanical clamp stays" (`:90-93`). Lesson for the ladder: labeled sections make constraints checkable, but mechanical enforcement stays regardless of good model behavior.
- `WORDLESS-ADHERENCE.md` (gen/wordless only; read via `git show gen/wordless:WORDLESS-ADHERENCE.md`): 8 audio-clause formats, 11 clips. Finding 2 is the brief's "instruction-following is probabilistic" citation, near-verbatim: "No wording is seed-proof. Seed 910910 defeated every variant tested on it… Prompt format shifts the distribution; it does not close the tap. Truly guaranteed silence needs a post-generation gate… or muxing out the vocal stem." This is the empirical basis for a server-owned `absurdity_level` and for pixels-over-prose (frame-chained i2v self-persists what's already rendered).
- WORDLESS finding 4 — the anti-pattern: "More words ≠ more suppression. The kitchen-sink combination (v8) had the worst hostile-seed result (33), worse than any of its ingredients alone." Stacking redundant ladder-enforcement prose into the prompt is counterproductive; one clean fragment per section beats belt-and-braces prose.
- WORDLESS finding 3: blunt stacked negatives degrade least — shipped as the `@vertical_suffix` audio clause on gen/wordless (commit bf48ae0). Note the three gen/* branches (speakless, wordless, omni) carry divergent suffix/prompt states; the escalation sprint inherits whichever base is chosen.

### 6. Vote option generation conventions

- Shape contract: exactly 3 strings, pinned three ways — system prompt rule (`prompts.ex:27`, lifted from `PLOT.md:98-121` §5, which the brief cites for escalation-form options), strict `json_schema` `minItems: 3, maxItems: 3` (`celeris.ex:132`), and mechanical clamp `choices/1`: trim, 120-char cap per option, reject empties, take 3, pad from `@fallback_choices` (`celeris.ex:195-205`).
- **No dedup exists** — duplicate options from the model would survive `choices/1`; the only guards are count and length.
- Flow: choices land in server state via `handle_pipeline({:celeris, result})` → `next_choices` (`episode_server.ex:262`), become the vote at `:vote_open` (`:161-176`), are preserved verbatim for revotes (`:188`), and the winner string passes as `ctx.winning_choice` (`:235`). Vote input validation is index-range only (`check_vote/2`, `episode_server.ex:334-341`). Escalation-form choices fit this pipe unchanged; what changes is what the prompt asks the model to generate.

### Anti-patterns / near-misses to flag

- **story_state merge order**: `Map.merge(state.story_state, story_state_updates)` at `episode_server.ex:255-256` — model-supplied updates win. If the brief's open question ("mirror the level into story_state?") is answered yes, a naive mirror is overwritable by the script engine, violating "the script engine never controls whether escalation happens." A mirror needs re-stamping after the merge or key protection.
- **Injection-path artifacts**: SPEAKLESS finding 4 (`SPEAKLESS-ADHERENCE.md:94-97`) — string-splicing constraint prose into model output produced a join artifact; the repo's chosen direction is structured blocks over spliced prose.
- **Prompt-only enforcement**: everywhere the repo cares, prompt requests are backed by mechanical clamps (`prompts.ex:38-39`, `:58-60`; `celeris.ex` moduledoc "defense in depth"). A ladder enforced only via the Celeris user prompt would break this doctrine — and the WORDLESS data shows why.
- **Fallback path bypass**: a ladder injection implemented inside the model-reply happy path (rather than `finalize/1` or later) would miss the canned fallback (`celeris.ex:215-236`) and retry paths — the fallback's video_prompts are unsectioned prose.

## Open questions

- Which branch does the escalation sprint build on? The sectioned video_prompt format the brief presumes exists only on `gen/speakless` (cb99238, 1 commit ahead of main); the WORDLESS suffix ships on `gen/wordless`; `gen/omni` adds VIDEO_ENGINE. Base/merge order is a planner call.
- No mechanism today parses video_prompts into named sections — Environment/Action are prompt-requested prose. Does "constrained into the Environment/Action sections" mean (a) section-aware post-parse injection (new machinery, `ensure_guard`-style), (b) appending labeled fragment lines like `suffix/1` does for Style, or (c) requiring/validating section presence in `clip/1`? Only precedents exist, no ready-made mechanism.
- If vote options become fixed-form escalation choices, does option generation stay with the script engine (prompt-shaped, clamp-backed) or move server-side like the level? The repo has both patterns; no precedent for server-authored options.
- Dedup of options is absent — does the escalation form (short noun phrases) make duplicates likelier and worth a mechanical guard?

## Sources

### Primary (HIGH confidence)
- `server/lib/whn/episode_server.ex`, `server/lib/whn/prompts.ex`, `server/lib/whn/celeris.ex`, `server/lib/whn/pipeline.ex`, `server/lib/whn/seed.ex`, `server/config/config.exs` — read in full.
- `server/test/test_helper.exs`, `server/test/whn/episode_server_test.exs`, `server/test/whn/celeris_test.exs`, `server/test/whn/pipeline_test.exs` (lines 1–110 + grep survey), `server/test/support/pipeline_stub.ex`, `server/test/support/fal_mock.ex` — read.
- `SPEAKLESS-ADHERENCE.md` (working tree) and `WORDLESS-ADHERENCE.md` (via `git show gen/wordless:WORDLESS-ADHERENCE.md`) — first-party empirical logs, read in full.
- `.jira/STATE.md`, `.jira/sprints/2026-09-02-frame-chained-continuity/CONTEXT.md`, `features/frame-chain.feature`, `PLOT.md` §5 — read.
- `git log --all --oneline`, `git diff main gen/speakless --stat` — branch topology facts.

### Secondary (MEDIUM confidence)
- Adherence-log conclusions generalized beyond their tested scenario (e.g. sectioned format helps ladder-fragment checkability) — the logs caveat single-scenario scope themselves (SPEAKLESS finding 3; WORDLESS n=1 reruns).

### Tertiary (LOW confidence)
- Inference that `pipeline_test.exs` beyond line 110 follows the surveyed assertion style throughout — grep-verified test names/assertion lines only, not read line-by-line.

---

**Confidence: HIGH** on repo conventions (all core files read in full on the gen/speakless checkout); MEDIUM only on generalizing the adherence experiments beyond their tested scenarios. One caveat: the sectioned-prompt surface exists only on gen/speakless, not main.
