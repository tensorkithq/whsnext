---
sprint: 2026-08-31-live-episode-mvp
plan: VI
wave: III
goal: One live episode runs the full loop — a vertical scene plays, the audience votes in a server-synced 10s window, and the locked winner generates the bridge and next scene via fal — proven by passing server test suites, a timed fal spike log, migrated Postgres tables, and a production build of the web client.
worktree: false
branch: jira/2026-08-31-live-episode-mvp
issue: none
depends_on: [I, III, IV]
parallel_with: []
files_modified:
  - server/lib/whn/prompts.ex
  - server/lib/whn/celeris.ex
  - server/lib/whn/pipeline.ex
  - server/test/support/fal_mock.ex
  - server/test/whn/celeris_test.exs
  - server/test/whn/pipeline_test.exs
covers:
  - D-05
  - D-14
  - D-15
  - "RESEARCH: LLM-JSON discipline (brace-slice, clamp, canned fallback); seed-per-beat + prompt_expansion_mode rules; FINAL FRAME HYGIENE + SOUND_CLAUSE prompt rules; Task.Supervisor.async_nolink beat-tagged generation; PLOT.md §5/§6/§15 choice-quality, bridge-vocabulary, and continuity rules"
  - "GOAL: locked winner generates the bridge and next scene"
effects:
  - CEL-01
  - CEL-02
  - CEL-03
  - CEL-04
  - CEL-05
  - CEL-06
---

# Plan VI: Generation pipeline — Celeris script engine + cycle orchestration

**Sprint goal:** One live episode runs the full loop — scene plays, audience votes in a server-synced 10s window, winner generates the continuation via fal — proven by tests, a spike log, migrations, and a web build.
**This plan delivers:** Track 3, part B. The Celeris script engine (README §5 JSON contract over the Celeris chat-completions API — REVISED D-05) and `Whn.Pipeline` implementing the pinned message contract: celeris → bridge → last frame → 3 chained 10s segments, winner-only, with retries and no vote reopening.

Everything tests against a mocked `Whn.Fal` impl — zero fal spend. Consult `.jira/sprints/2026-08-31-live-episode-mvp/fal-spike.log` (Plan III) before choosing any timeout values; use measured wall-clock × 3 as task timeouts.

## Tasks

### I. Prompts + Whn.Celeris — the script engine

- **Files:** `server/lib/whn/prompts.ex`, `server/lib/whn/celeris.ex`, `server/test/whn/celeris_test.exs`
- **Read first:** `README.md` §5 (exact JSON contract) + §12 (Celeris failure policy), `tmp/interdimensional-game/lib/adjudicator.ts` (system-prompt shape at :22-45, parse/clamp at :62-88, fallback at :219-252 — imitate the discipline, not the schema), `tmp/interdimensional-game/lib/worlds.ts:215-223` (SOUND_CLAUSE), `PLOT.md` §5, §6, §15, CONTEXT.md D-05/D-14/D-15
- **Action:** `Whn.Prompts`: `system_prompt/0` — instructs "Return ONLY compact JSON, no markdown fences, exactly this shape:" followed by the §5 contract verbatim (`scene_summary`, `winning_choice`, `bridge{duration,script,video_prompt}`, `next_scene{duration,script,video_prompt}`, `next_choices` (exactly 3), `story_state_updates{}`); embeds a FINAL FRAME HYGIENE rule ("every video_prompt must end on a readable, well-lit, stable frame — no close-ups, motion blur, or blackouts on the final beat — the last frame seeds the next shot"); a SOUND clause ("Sound: ambient environmental audio and cinematic score only; any voices are wordless — no spoken dialogue"); PLOT.md §5 choice rules (immediately understandable, socially debatable, consequential; never an obviously correct or stupid option); §6 bridge vocabulary and §15 continuity rules (callbacks, resource depletion, escalating stakes). `vertical_suffix/0` returns an exact style string (e.g. `"Vertical 9:16 smartphone cinematic, handheld, natural Lagos light."`) appended to every video_prompt. `user_prompt(ctx)` renders story_state, history, and winning_choice (or "OPENING — establish the premise and first decision" when nil). `Whn.Celeris.run(ctx) :: {:ok, result} | {:ok, :fallback, result}`: per REVISED D-05, POSTs via `Req` to `https://inference.celeris.ai/celeris-1/v1/chat/completions` with header `Authorization: Bearer <CELERIS_KEY>` (read via `System.fetch_env!/1` at call time; endpoint + key-env-name in app config so tests can point at a stub), body `%{model: "celeris-1", messages: [%{role: "system", content: system_prompt}, %{role: "user", content: user_prompt(ctx)}], temperature: 0.6, max_tokens: 700, seed: ctx.seed + ctx.beat, response_format: %{type: "json_schema", json_schema: %{name: "beat", strict: true, schema: <§5 contract as JSON Schema: scene_summary/winning_choice strings, bridge and next_scene objects with duration/script/video_prompt, next_choices array of exactly 3 strings, story_state_updates object>}}}`; reply content at `choices[0].message.content`. Structured output verified live this session: strict json_schema shaped the keys without prompt hints. Keep the brace-slice + clamp + fallback parsing unchanged as defense in depth. Text-only — no image attachment. Stub the HTTP in tests with `Req.Test` (plug-based) rather than a live call. Parse: slice first `{` to last `}`, `Jason.decode`, then clamp per-field — strings truncated, `next_choices` sliced/padded to 3, `bridge.duration` clamped 8..12 and `next_scene.duration` forced 30 (D-14), missing `video_prompt`/`script` invalidates. On invalid or `{:error, _}`: retry once, then return the canned fallback per D-15 (generic bridge: protagonist reacts and moves toward the consequence of `winning_choice`; reuse prior choices) — never raise, never reopen the vote. Append `vertical_suffix` to both video_prompts on the way out. Tests with an inline stub impl: CEL-01 (valid JSON → all six fields), CEL-02 (fenced JSON parses; garbage twice → fallback, no raise), CEL-03 (assert `system_prompt()` contains the hygiene + sound strings; assert both returned video_prompts end with `vertical_suffix()`).
- **Done when:** `(cd server && mix test test/whn/celeris_test.exs)` exits 0 (CEL-01..03); `grep -i 'final frame\|readable' server/lib/whn/prompts.ex` and `grep -i 'wordless' server/lib/whn/prompts.ex` match.
- **Covers:** D-05, D-14, D-15, RESEARCH LLM-JSON + prompt-rule findings

### II. Whn.Pipeline — winner-only cycle orchestration

- **Files:** `server/lib/whn/pipeline.ex`, `server/test/support/fal_mock.ex`, `server/test/whn/pipeline_test.exs`
- **Read first:** CONTEXT.md "Pinned interfaces" (pipeline callbacks + message shapes — conform exactly), `server/lib/whn/fal.ex` and `server/lib/whn/frames.ex` (Plan III, merged), `tmp/interdimensional-game/lib/fal.ts:40-53` (param contract), `server/AGENTS.md` (task idioms)
- **Action:** `Whn.Pipeline` defines the behaviour (`start_opening/2`, `start_cycle/2`) and implements it: `Task.Supervisor.start_child(Whn.TaskSupervisor, fn -> run(dest, ctx) end)`. `start_cycle`: (1) `Celeris.run(ctx)` → send `{:pipeline, beat, {:celeris, result}}`; (2) bridge via `Whn.Fal.i2v(bridge.video_prompt, ctx.last_frame_url, duration: 10, resolution: "480P", prompt_expansion_mode: "disabled", seed: ctx.seed + ctx.beat)` (if `last_frame_url` is nil, `t2v` with `aspect_ratio: "9:16"`, `prompt_expansion_mode: "balanced"`) → send `{:bridge_ready, url}`; (3) `Whn.Frames.last_frame(bridge_url)`; (4) three segments, chained: for `seg_idx <- 0..2`, `i2v("#{next_scene.video_prompt} Continuation, part #{seg_idx + 1} of 3.", frame_url, duration: 10, resolution: "480P", prompt_expansion_mode: "disabled", seed: ctx.seed + ctx.beat)` → send `{:segment_ready, seg_idx, url}` → `Frames.last_frame(segment_url)` feeds the next iteration. `start_opening`: Celeris opening (bridge nil) → `Whn.Fal.flux(opening frame prompt from premise, image_size: %{width: 720, height: 1280}, seed: ctx.seed)` → 3 chained i2v segments as above (no bridge messages). Every fal/frames stage wrapped in `with_retry/1`: one retry with identical args (same seed — idempotency per D-15); on second failure send `{:pipeline, beat, {:error, stage, reason}}` and stop. `FalMock` in test/support: implements the `Whn.Fal` behaviour, logs every call `{fun, args}` to an Agent, returns scripted responses (including a fail-once mode). Tests (set `:fal_impl` to `FalMock`, dest = `self()`, `assert_receive` in order): CEL-04 (celeris → bridge_ready → segment_ready 0,1,2), CEL-05 (assert i2v opts: "480P"/10/"disabled"/seed = seed+beat; opening flux gets 720x1280), CEL-06 (fail-once on segment 0 → exactly 2 calls with identical seed, no `{:error, ...}` message).
- **Done when:** `(cd server && mix test test/whn/pipeline_test.exs)` exits 0 (CEL-04..06); `grep 'seed + ' server/lib/whn/pipeline.ex` (or `ctx.seed + ctx.beat`) matches.
- **Covers:** D-15, RESEARCH seed-per-beat/expansion-mode/task-supervision findings

## Nyquist criteria for this plan

- [ ] §5 contract parses into the pinned result shape (CEL-01)
- [ ] Fenced/garbage LLM output → brace-slice / canned fallback, never a crash (CEL-02)
- [ ] Hygiene + sound rules in the system prompt; vertical suffix on every video_prompt (CEL-03)
- [ ] Stage messages arrive in pinned order (CEL-04)
- [ ] Reference param contract honored, seed = episode seed + beat (CEL-05)
- [ ] One idempotent retry per stage before error (CEL-06)

## Risks accepted in this plan

- Real fal behavior (latency distribution, prompt quality) is only sampled by the Plan III spike; live tuning happens post-sprint. The hold state absorbs overruns.
- Segment prompting reuses `next_scene.video_prompt` with a part-suffix rather than per-segment scripts — continuity rides on frame chaining + disabled expansion (Claude's-discretion note in CONTEXT.md).
- Bridge duration returned by Celeris (8–12s) is advisory; generation always requests 10s clips this sprint.
- The pipeline trusts `dest` to apply its own stale-beat guard (Plan IV does).
