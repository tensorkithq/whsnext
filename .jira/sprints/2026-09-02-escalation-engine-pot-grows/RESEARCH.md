# Research: 2026-09-02-escalation-engine-pot-grows

**Date**: 2026-09-02
**Domain**: backend/elixir — live-episode GenServer + LLM/video-generation prompt pipeline
**Confidence**: HIGH
**Valid until**: 2026-09-16 — line cites are pinned to `gen/speakless` HEAD `cb99238` (one commit ahead of main) and the fal model-parameter surface moves fast; both go stale quickly. See Metadata.

## Summary

The escalation engine lands on unusually favorable ground. The +1-on-canonized-lock semantics the issue demands already exists structurally: `lock_and_start_cycle/2` (`server/lib/whn/episode_server.ex:218-244`) is the *only* code path where a vote canonizes, and it already bumps `beat` at `:231`; the below-quorum branch (`:183-189`) and `:revote` (`:205-214`) never reach it, so "no bump on revote" falls out of clause structure, not a new guard. The ctx has a single constructor, `pipeline_ctx/2` (`:432-442`), covering all three dispatch sites — one new key there exposes the level to the pipeline, but the ctx shape is a pinned cross-sprint contract (frame-chained CONTEXT.md D-01, "binding on this and future sprints"), so adding `absurdity_level` is a formal contract amendment.

The one genuine gap: "constrained into the video_prompt Environment/Action sections" has no existing mechanism. The sectioned format (Camera/Environment/Action/Dialogue, commit cb99238) is *requested* in the system prompt (`prompts.ex:23`), never parsed or validated; the only mechanical constraints today are the dialogue guard (`prompts.ex:49-105`) and the Style suffix append, both applied in `Celeris.finalize/1` (`celeris.ex:238-244`) — the natural seam for mechanical ladder injection. External evidence both supports and sharpens the design's load-bearing assumption: i2v models demonstrably prioritize the conditioning image over prose (arXiv 2601.07287, 2511.15700 — "escalation baked into pixels self-persists" is real), but the flip side is that a prose fragment asking the pot to *grow mid-clip* is the weak link (entity-size prompt-following ~3/5 even on top models). The prose ladder keeps the model from fighting the image; it does not guarantee the bump lands in pixels — the strong tool for that is `end_image_url` FLF conditioning, which this repo already deferred once (STATE.md).

On the issue's open question (mirror the level into story_state?), the codebase gives a hard answer: the merge at `episode_server.ex:255-256` is updates-win — a mirrored key is silently clobber-able by the model's `story_state_updates`, violating "never trusted to the script engine." Server-side-only (ctx field + prompt line rendered from ctx) is clobber-proof with zero extra code. Both adherence logs (SPEAKLESS on this branch, WORDLESS via `git show gen/wordless:WORDLESS-ADHERENCE.md`) ground the server-owned design empirically — "no wording is seed-proof; prompt format shifts the distribution; it does not close the tap" — and warn that kitchen-sink prose stacking makes adherence *worse*: one clean fragment per surface.

**Primary recommendation:** copy the `beat` counter pattern for `absurdity_level` (init at `:60`-adjacent, +1 beside the beat bump at `:231`, expose via `pipeline_ctx/2`, keep it out of story_state); inject the ladder fragment as a labeled line in `Prompts.user_prompt/1` and mechanically in `Celeris.finalize/1` (where Style is already appended); make vote options escalation-form via system-prompt rules backed by the existing choices clamp; test all three acceptance assertions with the existing PipelineStub-ctx / FalMock-calls patterns.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|---|---|---|---|
| Own/bump `absurdity_level` | API/Backend (EpisodeServer state) | — | `episode_server.ex:53-77` (init), `:218-244` — the only canonization path |
| Expose level to pipeline ctx | API/Backend | — | `pipeline_ctx/2` at `:432-442`; pinned contract amendment (frame-chained CONTEXT.md D-01) |
| Ladder fragments (fixed text L0–L5) | API/Backend module constants | Seed attrs (premise-specific override) | precedent `prompts.ex:10-30`, `celeris.ex:23-27`; attrs path like `story_state` at `episode_server.ex:68` |
| Inject into Celeris user prompt | API/Backend | — | labeled-line convention, `prompts.ex:111-128` |
| Constrain into video_prompt Env/Action | API/Backend (new machinery) | — | seam: `Celeris.finalize/1` (`celeris.ex:238-244`); dialogue guard is the house pattern (`prompts.ex:49-105`) |
| Escalation-form vote options | API/Backend (prompt rules + clamp) | — | `prompts.ex:27` (rule), `celeris.ex:132,195-205` (shape), `episode_server.ex:161-176,262` (flow) |
| No bump on revote | API/Backend | — | falls out of `episode_server.ex:183-189,205-214` never reaching `:218` |
| Level persistence (if any) | Database/Storage | — | `store.ex:56-61` (story_state, model-writable) or a new episode/beat column; nothing reads persisted state at runtime today |
| Options display | Browser/Client — no change | — | options are opaque strings over `vote_open`; wire protocol untouched |

## Codebase

All cites at `gen/speakless` HEAD `cb99238`. Full detail in `research-codebase.md`.

- **Existing:**
  - Lock vs revote is structurally clean: `lock_and_start_cycle/2` (`episode_server.ex:218-244`) computes the winner (D-02 tie-break `:219-222`), broadcasts, persists, bumps `beat: state.beat + 1` (`:231`), builds ctx (`:235`), dispatches or parks (`:237-243`). Below-quorum (`:183-189`) closes, schedules `:revote`, never touches beat — test-asserted at `episode_server_test.exs:141`. The level `+1` is one line beside the beat bump; L0 is the init value (the opening never passes through lock).
  - `pipeline_ctx/2` (`:432-442`): `%{beat, seed, episode, story_state, winning_choice, last_frame_url, history}`. The parked-cycle refresh (`:149`) patches only `last_frame_url`; a level snapshotted at lock is already post-bump — no refresh needed.
  - Celeris user prompt is one heredoc, `Prompts.user_prompt/1` (`prompts.ex:111-128`), UPPERCASE labeled lines; `story_state` in via `Jason.encode!` (`:115`). A ladder line (e.g. `ESCALATION (L2): ...`) slots in keyed off `ctx.absurdity_level`.
  - Vote options: model `next_choices`, schema-pinned to exactly 3 (`celeris.ex:132`), clamped/padded in `choices/1` (`:195-205`), stored (`episode_server.ex:262`), polled (`:161-176`), preserved verbatim across revotes (`:188`). Escalation-form choices are a prompt-rules change riding this pipe unchanged.
  - Sectioned video_prompt is **requested, not enforced** — the only mechanical constraints are the dialogue guard and the Style suffix append, both in `Celeris.finalize/1` (`celeris.ex:238-244`). Fallback prompts flow through `finalize/1` too (`celeris.ex:44`), so a fragment injected there reaches the canned-fallback video_prompts — but `@fallback_choices` (`:23-27`) and the fallback beat (`:215-236`) stay non-escalation-form.
  - story_state merge is updates-win (`episode_server.ex:255-256`), persisted wholesale (`:397-408` → `store.ex:56-61`), consumed only by `user_prompt/1`. A mirrored level is model-clobber-able.
- **Would change:** `server/lib/whn/episode_server.ex` (state key, +1, ctx field), `server/lib/whn/prompts.ex` (ladder constants, user-prompt line, system-prompt rules; possibly an Env/Action injection helper), `server/lib/whn/celeris.ex` (`finalize/1` injection; fallback if made ladder-aware), the three test files (`episode_server_test.exs`, `celeris_test.exs`, `pipeline_test.exs`), plus the sprint's ctx-contract amendment in CONTEXT.md.
- **Reference-only:** `pipeline.ex` (unless bridge/segment prompts get separate fragment treatment — note `run_segments/5` reuses the scene prompt for all 3 segments, `pipeline.ex:110-125`, so injected prose rides into every segment), `seed.ex` + `seeds.exs` (premise seeding is #11), `store.ex` + schemas (unless the level persists), `test/support/*` (stub/mock already sufficient), all of `web/`.
- **Injection caveat:** `clamp_dialogue`'s `squeeze/1` (`prompts.ex:100-105`) collapses 2+ whitespace across the whole prompt when a quoted line exists — injected fragments must survive it (single `\n` survives; blank lines don't).

## Patterns & conventions

Full detail in `research-patterns.md`.

- **To imitate:**
  - The `beat` counter (`episode_server.ex:60` init, `:231` bump) — the exact template for a server-owned monotonic integer.
  - House guarded-head style for timeline events (guarded clause + silent fall-through, `:180/:192`, `:198/:203`; frame-chained CONTEXT.md D-06).
  - Mechanical enforcement doctrine: "Enforced mechanically, not just requested: the model's output is untrusted like every other field" (`prompts.ex:38-39`); every constraint the repo cares about is backed by a post-parse clamp (`clamp_dialogue`, `strip_dialogue`, forced `duration: 30` at `celeris.ex:172`, choice clamp). A ladder enforced only via the Celeris user prompt would break this doctrine — and the WORDLESS data shows why.
  - Fixed data tables as module attributes beside their consumer (`@default_timings`, `@vertical_suffix`, `@fallback_choices`); premise-specific content via seed attrs → `init` (the `story_state`/`min_voters`/`timings` shape). The two compose: attribute default, attrs override — the route that keeps #11's premise-specific fragments possible without new machinery.
  - Test house rules (binding, `server/AGENTS.md:69-78`): `start_supervised!`, no sleeps, `:sys.get_state` sync barriers, tests drive every timeline event manually; hermetic env (`test_helper.exs:1-8` deletes engine vars, cf79d87); requirement-tag comments tied to `features/*.feature` Gherkin with a fresh id series per sprint (frame-chained CONTEXT.md D-07). The three demanded assertions map 1:1: ctx bump ≙ `episode_server_test.exs:68-70`; no-bump ≙ `:126-143` (extend the `beat == 0` assert) and `:145-168` (revote-then-quorum ctx carries level 1, not 2); fragment-in-emitted-prompt ≙ `celeris_test.exs:166-201` (finalize output) and `pipeline_test.exs:183-215` (FalMock-captured i2v prompts).
  - Adherence-log lessons (the design's empirical ground): WORDLESS finding 2 — "No wording is seed-proof… Prompt format shifts the distribution; it does not close the tap" — is the basis for server-owned level and pixels-over-prose. SPEAKLESS: sectioned prompts won on *structural checkability*, not adherence; the mechanical clamp stays regardless of good model behavior.
- **To deliberately not imitate:**
  - Kitchen-sink prose stacking — WORDLESS finding 4: the v8 clause pile had the *worst* hostile-seed result, worse than any ingredient alone. One clean fragment per section beats belt-and-braces prose.
  - String-splicing constraint prose into model output — SPEAKLESS finding 4: the old marker-injection path produced a join artifact ("falls silent.then he says nothing more"); the repo's direction is structured blocks over spliced prose (`ensure_guard`-style labeled insertion, or plain append like the Style suffix).
  - A naive story_state mirror of the level — clobber-able at the updates-win merge (`episode_server.ex:255-256`).
  - Happy-path-only injection — anything implemented inside the model-reply parse (rather than `finalize/1` or later) misses the canned fallback (`celeris.ex:215-236`) and retry paths.

## Standard Stack

No new dependencies recommended. Candidates evaluated (from `research-external.md`):

### Supporting

| Mechanism | Where | Purpose | When to Use |
|---|---|---|---|
| FLF conditioning (`end_image_url`) | fal Seedance 2.0/2.5 i2v, Kling O1/O3 APIs | Force a size-class transition to land: render the next size class as a still, interpolate toward it | If prose-only escalation proves visually unreliable; matches the already-deferred "end_image_url keyframe bridges" (STATE.md) |
| VLM frame check | GPT-4o-class on the extracted frame | Detect a regressed pot before seeding the next clip | Only with majority-of-3 (single-run F1 0.79, arXiv 2508.04895); adds cost + lock→dispatch latency — defer unless drift shows up |
| Negative prompts against shrinkage | Kling `negative_prompt` param | Guard against scale regression | Not portable — Seedance 2.0 exposes no negative prompt; inline prohibitions are the only cross-model form and can backfire (naming "small pot" puts it in the conditioning) |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|---|---|---|
| Prose ladder fragment only | Image-edit round trip (enlarge pot in the extracted frame, then i2v) | Converts prose hope into image guarantee; one extra model call per lock; untested vs FLF for stepwise growth |
| Hand-rolled validate-and-retry for options | `instructor_ex` / `InstructorLite` | Packages schema-validate + retry over OpenAI-compatible APIs; only pays off if validation grows Ecto-shaped — D-15's one-retry pattern already covers the floor |

## Don't Hand-Roll

Inverted here — the trap is *adopting*, not building:

| Problem | Don't Adopt | Use Instead | Why |
|---|---|---|---|
| L0–L5 fragment table + interpolation | `langchain` hex (PromptTemplate) | Module attribute in `Whn.Prompts` (precedent `prompts.ex:10-30`) | PromptTemplate is EEx with bookkeeping; six strings don't earn a dependency whose chat abstractions the repo already bypasses (D-05 raw Celeris) |
| Options schema validation + retry | `instructor_ex` (for now) | Existing strict `json_schema` (`celeris.ex:132`) + `choices/1` clamp (`:195-205`) + D-15 retry | No schema can express "three variations of one beat" anyway — semantic post-validation is required regardless of transport |

**Key insight:** the ladder is static data plus mechanical injection at an existing seam; every needed primitive (counter pattern, clamp pattern, retry pattern, test pattern) already exists in-repo.

## Common Pitfalls

### 1. Mid-clip growth via prose silently fails

- **What goes wrong:** the emitted clip shows the L(n) pot doing the L(n+1) action, or no size change at all.
- **Why it happens:** i2v models prioritize the conditioning image and internal priors over text (arXiv 2601.07287); entity-size instruction-following scores ~3/5 even on top models (arXiv 2604.14148). The seed frame shows the old size.
- **How to avoid:** treat the fragment's reliable job as *describing what the seed frame already shows* and steering action flavor, not introducing unseen size changes; escalate at seed-image boundaries; keep FLF `end_image_url` as the named fallback tool.
- **Warning signs:** live smoke shows scale lagging the level by one; ladder fragment present in prompt but absent in pixels.

### 2. Chained-frame drift can undo escalation

- **What goes wrong:** color/identity drift and pot proportions regressing toward the model's "normal kitchen pot" prior across chained clips.
- **Why it happens:** exposure bias compounds per link — visible by extension 2–3, severe by ~10 (FramePack); a 6-level episode is ~6+ links (scenes plus bridges), inside the danger zone.
- **How to avoid:** the ladder fragment describing the *current* size in every prompt is the cheap mitigation (prose agreeing with pixels); practitioner playbook if it bites: full-res extraction, frame re-mint, reference re-anchoring, chain caps.
- **Warning signs:** pot visually smaller at L4 than L3 in a live smoke; color/contrast shift across beats.

### 3. t2v fallback breaks the pixel chain at high levels

- **What goes wrong:** frame extraction fails → t2v fallback regenerates from prose only (STATE.md frame-chaining decision) — precisely the modality with weak size adherence. At L4 nothing but the fragment holds up a hut-sized pot.
- **Why it happens:** the fallback discards the conditioning image, the design's actual persistence mechanism.
- **How to avoid:** accept as degradation (existing repo posture: extraction failure never holds the episode) but make sure the ladder fragment *is* in the t2v prompt — it's the only escalation carrier on that path.
- **Warning signs:** post-fallback clips at normal scale; `last_frame_url: nil` beats at level ≥ 2.

### 4. Model-clobbered level via story_state

- **What goes wrong:** a level mirrored into `story_state` is silently overwritten by one `story_state_updates` echo — the script engine ends up controlling escalation, violating the design's core rule.
- **Why it happens:** `Map.merge(state.story_state, updates)` at `episode_server.ex:255-256` — model updates win; `updates/1` does no key filtering (`celeris.ex:207-208`).
- **How to avoid:** keep the level server-side-only (ctx + prompt line rendered from ctx). If mirroring is chosen anyway, re-stamp the server value after the merge at `:255-256`.
- **Warning signs:** a test seeding `story_state_updates` with the level key changes the emitted fragment.

### 5. Escalation-form options that aren't

- **What goes wrong:** options name different beats ("stir with paddle" / "add more pepper" / "leave the kitchen") — the vote decides *whether*, not *how*, breaking PLOT.md §5 semantics. Structured outputs guarantee JSON shape, not "three variations of one beat"; prompt-only JSON fails 1–20% by schema complexity.
- **Why it happens:** semantic constraints are inexpressible in schema; `choices/1` guards only count and length; **no dedup exists** — duplicates survive the clamp (`celeris.ex:195-205`). Celeris support for strict `response_format: json_schema` is unverified (OpenAI-compatible ≠ structured outputs).
- **How to avoid:** system-prompt rule change + keep the strict schema + consider a cheap mechanical check (dedup at minimum); double-failure lands on `@fallback_choices`, which are non-escalation-form (`celeris.ex:23-27`) — decide whether the fallback becomes ladder-aware.
- **Warning signs:** duplicate or off-form options in `vote_open` payloads in tests seeded with adversarial Celeris replies.

### 6. Injection formatting destroyed by `squeeze/1`

- **What goes wrong:** an injected multi-line or blank-line-separated fragment collapses to one line in the final prompt.
- **Why it happens:** `clamp_dialogue`'s `squeeze/1` collapses 2+ whitespace across the whole prompt whenever a quoted line exists (`prompts.ex:100-105`).
- **How to avoid:** single-`\n` labeled lines (the Style-suffix shape); assert exact formatting in `finalize/1` tests.
- **Warning signs:** fragment present but mangled in FalMock-captured prompts.

## SOTA Updates

| Old Approach | Current Approach | When Changed | Impact |
|---|---|---|---|
| Single-image i2v + prose steering | First/last-frame conditioning as a first-class API param (fal Seedance 2.x, Kling O1/O3) | 2025–26 | A pot-growth transition can be *interpolated between two constraints* instead of hoped for — the named upgrade path if prose-only escalation underdelivers |
| "Output valid JSON" + few-shot (1–20% failure) | Strict-schema constrained decoding, ~100% syntactic validity where supported | OpenAI Aug 2024 onward | Support across OpenAI-*compatible* endpoints (Celeris) inconsistent — post-validation stays the portable floor |

**Deprecated:** nothing in-repo; note the three `gen/*` branches carry divergent prompt states (speakless: sectioned format; wordless: audio suffix; omni: VIDEO_ENGINE).

## Risks & unknowns

- **Base branch** — the sectioned video_prompt format the issue presumes exists only on `gen/speakless` (cb99238, exactly one commit ahead of main); WORDLESS suffix on `gen/wordless`, VIDEO_ENGINE on `gen/omni`. Which base (and merge order) does this sprint build on? Repo rule says branch off main — cb99238 must land on main first or the sprint stacks on gen/speakless. Resolving: a decision at plan time; check whether cb99238 is merge-ready.
- **"Constrained into Env/Action" semantics** — no parser for sections exists; options are (a) `ensure_guard`-style parse-and-insert, (b) plain labeled append like the Style suffix, (c) validate-presence in `clip/1`. Resolving: planner picks one; SPEAKLESS's join-artifact history favors (b)'s simplicity or (a)'s label discipline over prose splicing.
- **Prose ≠ pixels for the actual growth moment** — the ladder fragment cannot guarantee the size bump lands visually (Pitfall 1); FLF `end_image_url` is the strong tool but was explicitly deferred last sprint. Resolving: decide whether this sprint is prompt-plumbing only (accept probabilistic visuals, verify by live smoke) or includes a keyframe/image-edit mechanism.
- **Celeris `response_format` support unknown** — determines how hard escalation-form options can be pinned. Resolving: one-call probe against the live endpoint, or rely on post-validation only.
- **Fallback-path degradation** — canned fallback options/prompts are non-escalation-form; double Celeris failure yields a non-ladder beat. Resolving: planner decides in-scope vs accepted degradation.
- **Level persistence** — in-memory only dies with the process; nothing reads persisted state at runtime today and restart recovery has been out of scope both prior sprints. Resolving: planner confirms out of scope again or adds a column.
- **Ladder shape vs #11** — generic L0–L5 module attribute vs premise-specific fragments via seed attrs (Amaka's pot). The attrs-override composition keeps both; the current seed (Salary Just Entered) has no pot at all, so hermetic tests must not assume the premise.

## Open questions for planner

1. Base branch: stack on `gen/speakless` (has the sectioned format) or land cb99238 on main first and branch from main per repo rule?
2. Mirror `absurdity_level` into story_state (needs merge re-stamp at `episode_server.ex:255-256`) or server-side-only? (All three research files point server-side-only; the issue text also leans that way.)
3. Mechanical injection form for the video_prompt: labeled append à la Style suffix, or section-aware insert à la `ensure_guard`? And does the fragment also shape the **bridge** prompt and the **opening flux still** (`pipeline.ex:51,90-92`), or only `next_scene`?
4. Ladder home: generic module attribute in `Whn.Prompts`, seed-attrs override for premise-specific sets (issue #11 compatibility), or both (default + override)?
5. Is the canned Celeris fallback (`celeris.ex:23-27,215-236`) made ladder-aware in this sprint, or accepted as non-escalation degradation?
6. Option dedup: add a mechanical guard in `choices/1` (none exists today), or leave it?
7. What happens above L5 — clamp at max, or is the ladder sized to the format's 6 locks (issue #9: finale at minute 4)? Level count and #9's beat arithmetic should agree.
8. Does the level persist (episode/beat column) for restart recovery, or in-memory only like the rest of episode state?
9. Ctx-contract amendment: record `absurdity_level` as a formal amendment to frame-chained CONTEXT.md D-01 in this sprint's CONTEXT.md.

## Sources

### Primary (HIGH confidence)

- `server/lib/whn/{episode_server,celeris,prompts,pipeline,store,seed,episodes}.ex`, `server/lib/whn/schemas/{episode,beat}.ex`, `server/priv/repo/seeds.exs` — read in full at HEAD `cb99238` (research-codebase.md).
- `server/test/whn/{episode_server_test,celeris_test,pipeline_test,integration_test}.exs`, `server/test/support/{pipeline_stub,fal_mock}.ex`, `server/test/test_helper.exs`, `server/AGENTS.md:69-78` — read (both codebase and patterns files).
- `SPEAKLESS-ADHERENCE.md` (working tree), `WORDLESS-ADHERENCE.md` (`git show gen/wordless:WORDLESS-ADHERENCE.md`) — first-party adherence experiments; the design rationale's source.
- `.jira/STATE.md` (D-01..D-16 + frame-chaining decisions), `.jira/sprints/2026-09-02-frame-chained-continuity/CONTEXT.md` (pinned ctx contract), `PLOT.md` §5 (`PLOT.md:97-121`).
- GitHub issues #8 (brief), #9/#10/#11 (adjacent scope) — tensorkithq/whn.
- arXiv 2601.07287 (Focal Guidance — i2v prioritizes visual condition over text), 2511.15700 (first frame as conceptual memory buffer), 2604.14148 (Seedance 2.0 tech report — entity-size ~3.13/5), 2508.04895 (VLM non-determinism F1 0.79), 2411.04709 (TIP-I2V).
- fal API docs: Seedance 2.0/2.5 i2v, Kling O1/O3 (`end_image_url` surface); Mike Booth (Valve), "The AI Systems of Left 4 Dead" (slides PDF); Riedl & Bulitko, AI Magazine 34(1) 2013; OpenAI structured-outputs announcement + pricing; FramePack project page; instructor_ex / LangChain.PromptTemplate docs.

### Secondary (MEDIUM confidence)

- Prior sprint's research-codebase.md — line numbers predate cb99238; every reused claim re-verified against current source.
- Adherence-log conclusions generalized beyond their tested scenario (the logs caveat single-scenario scope themselves).
- fal learn Seedance-vs-Kling comparison; Kling start/end-frame guide; L4D wiki + CenterConsulting summaries (agree with the primary Booth talk); Let's Data Science structured-outputs explainer; HackerNoon drift article (403 on direct fetch, search-corroborated); drama-management survey (listing only).

### Tertiary (LOW confidence)

- Tensoria structured-output failure rates (5–20%/1% — plausible, unbenchmarked).
- Practitioner drift guides (MobileMall, Renoise, MagicHour, Hailuo, OCDevel podcast) — techniques mutually agree; specific numbers ("cap at two extensions") are folklore.
- invideo/Artlist negative-prompt posts.
- pipeline_test.exs beyond line 110 assumed to follow the surveyed assertion style (grep-verified only).

## Metadata

**Research scope:**
- Focus areas covered: codebase, patterns, external
- Sections omitted: none. Standard Stack retained despite zero new deps (documents the FLF/VLM/instructor evaluations and why they're deferred). Don't Hand-Roll inverted (the trap here is adopting, not building).

**Confidence breakdown:**
- Codebase findings: HIGH — every claim `path:line`-cited from files read in full at HEAD cb99238.
- Patterns & conventions: HIGH on repo conventions (core files read in full); MEDIUM on generalizing the adherence experiments beyond their tested scenarios.
- Standard stack: HIGH on the fal FLF API surface and prior-art pattern; MEDIUM on drift thresholds and structured-output failure rates (practitioner/blog-sourced numbers, tiered accordingly).
- Pitfalls: HIGH for the four grounded in repo code + peer-track papers; MEDIUM for drift-rate specifics and VLM figures.

**Cross-cut notes (synthesis):**
- No contradictions between focus files. One tension recorded as a risk: external evidence says prose alone won't reliably land the growth moment in pixels, while the issue's scope is prompt-plumbing — resolved as planner question 3/“prose ≠ pixels” risk, with FLF as the named upgrade path (already deferred once, STATE.md).
- Codebase and patterns agree independently on the two central calls: `beat`-counter template + `finalize/1` seam, and server-side-only level (merge-clobber hazard found by both).
- WORDLESS anti-pattern (clause stacking degrades adherence) constrains how the ladder is injected: one clean fragment per surface, not belt-and-braces repetition.

**Valid-until reasoning:** 14 days. Line cites pin to `gen/speakless` HEAD cb99238 — any merge to main shifts them; the fal model-parameter surface (`end_image_url`, negative prompts) is fast-moving; the gen/* branch topology is expected to change as #8–#11 land.

---

*Sprint: 2026-09-02-escalation-engine-pot-grows*
*Research completed: 2026-09-02*
*Next step: `/jira:plan`*
