---
sprint: 2026-09-02-escalation-engine-pot-grows
created: 2026-09-02
status: locked
---

# Context: 2026-09-02-escalation-engine-pot-grows

Locked decisions for this sprint. The user approved proceeding to plan (issue #8 brief, research agent report user-selected over 4 alternatives); the orchestrator delegated the open questions that are decidable from RESEARCH.md and house doctrine. Once written here, decisions are NON-NEGOTIABLE for downstream agents.

## Phase boundary

This sprint ships the escalation engine's plumbing: a server-owned `absurdity_level` (+1 per canonized lock, never on revote), a fixed L0–L5 ladder of prompt fragments injected into the Celeris user prompt and mechanically appended to every outgoing video prompt, and escalation-form vote options via system-prompt rules plus a mechanical dedup. All changes live in `server/`; **zero changes under `web/`** (options are opaque strings, wire protocol frozen). OUT of scope: finale mode / episode clock (#9), style presets (#10), seeding Amaka's Cooking Contest (#11) — the ladder design merely must not preclude premise-specific fragment sets. Escalation landing *in pixels* is probabilistic by design (prose agrees with the frame chain; FLF keyframes stay deferred) — this sprint is verified hermetically, live visual fidelity awaits a production smoke.

## Decisions

- **D-00 (goal restatement):** The sprint goal, measurable: `EpisodeServer` owns `absurdity_level` (init 0, +1 at each canonized vote lock only — below-quorum closes and revotes never bump — and clobber-proof against `story_state_updates`), exposed via the pipeline ctx; a fixed L0–L5 ladder of Environment/Action fragments is rendered as a labeled `ESCALATION (Ln):` line in the Celeris user prompt and mechanically appended as a labeled `Escalation:` line to every outgoing video prompt (scene, bridge, canned fallback, all three segments, opening still); vote options are escalation-form per rewritten system-prompt rules backed by a mechanical dedup — proven by the server suite passing with all 11 EL- predicates sensed and `mix test` exiting 0. *(planner restatement of issue #8's acceptance criteria; adds verification surface, reduces nothing)*
- **D-01 (base branch):** Branch `jira/2026-09-02-escalation-engine-pot-grows` off `gen/speakless` (HEAD cb99238 + sprint bookkeeping); the PR targets `main` and carries cb99238 with it. Rationale: the sectioned video_prompt format the issue presumes exists only on `gen/speakless`; it is exactly one code commit ahead of main with a green suite, so stacking is safe and avoids a ceremony-only pre-merge. `gen/wordless`/`gen/omni` stay untouched experiment branches.
- **D-02 (server-owned level, no story_state mirror):** `absurdity_level: 0` joins the `init/1` state map beside `beat`; the +1 lands in `lock_and_start_cycle/2`'s state update beside the beat bump; `pipeline_ctx/2` gains the key. The level is NEVER mirrored into `story_state`: the merge at `episode_server.ex:255-256` is updates-win, so a mirrored key is silently model-clobber-able — violating the issue's "never trusted to the script engine". All three research files are unanimous. The script engine learns the level only from the rendered prompt line (D-05).
- **D-03 (ctx-contract amendment):** The pinned pipeline ctx contract (frame-chained CONTEXT.md D-01, binding on this and future sprints) gains exactly one key. Updated ctx shape, restated in full and binding henceforth:

  ```elixir
  # ctx: %{beat, seed, episode: %{title, premise}, story_state, winning_choice (nil for opening),
  #        last_frame_url (nil for opening), history: [scene_summary, oldest first],
  #        absurdity_level (integer >= 0; 0 for the opening; NEW)}
  ```

  The key is required (strict access, no `Map.get` default): a ctx missing it must crash loudly, not silently emit L0 forever. The parked-cycle refresh at `episode_server.ex:149` needs no change — the level is snapshotted post-bump at lock and cannot go stale during a hold the way frames can. All message shapes from the prior contract remain binding unchanged.
- **D-04 (ladder home and shape):** The ladder is a 6-element module attribute `@ladder` in `Whn.Prompts` (precedent: `@system_prompt`, `@vertical_suffix`, `@fallback_choices`), exposed through a single public accessor `Prompts.escalation_fragment(level)` that clamps the index with `min(level, 5)`. The accessor is the ONLY lookup point — issue #11's premise-specific fragment sets can later thread seed attrs through it without new machinery (attribute default, attrs override; the composition research names). Default fragments describe the pot ladder from issue #8 with a premise-neutral protagonist. No seed/attrs plumbing this sprint.
- **D-05 (injection mechanism — labeled single-line appends, three surfaces):** One clean fragment per surface (WORDLESS finding 4: clause stacking degrades adherence; SPEAKLESS finding 4: no prose splicing):
  1. **Celeris user prompt:** one labeled line `ESCALATION (L#{min(level, 5)}): #{fragment}` rendered in `Prompts.user_prompt/1` directly after the STORY STATE line, keyed off `ctx.absurdity_level`.
  2. **Video prompts (mechanical):** `Celeris.finalize/1` becomes `finalize/2` taking the level (all three call sites in `run/1` pass `ctx.absurdity_level`); it appends `"\nEscalation: " <> fragment` to BOTH the bridge and next_scene video_prompts, after `strip_dialogue`/`clamp_dialogue` (so the single `\n` is appended post-`squeeze/1` and survives) and BEFORE the Style suffix (existing tests pin `String.ends_with?(vp, vertical_suffix())`). Bridges carry it because pixels persist through bridges too. Fallback video_prompts get it for free — the fallback flows through `finalize` (`celeris.ex:44`). Segments inherit it via the shared scene prompt (`pipeline.ex:110-125`).
  3. **Opening flux still:** `Pipeline.opening_prompt/1` renders the fragment at `ctx.absurdity_level` (0 at opening) — the L0 anchor baked into the very first conditioning image.
- **D-06 (escalation-form vote options):** System-prompt rules change riding the existing pipe unchanged: a new `ESCALATION:` rules bullet (the ESCALATION line is story truth; render Environment/Action consistent with it; the model never decides *whether* escalation happens) and a rewritten `next_choices` bullet (exactly 3 distinct ways to visibly handle the situation at its current scale — three forms of the same next beat, never whether; PLOT.md §5 conditions preserved; no duplicates). The mechanical floor stays: strict `json_schema` 3-item pin + `choices/1` clamp + D-08 dedup. Semantic "three forms of one beat" is inexpressible in schema — accepted as prompt-governed, tested by system-prompt content assertion.
- **D-07 (fallback posture):** The canned fallback's video_prompts become ladder-aware for free via `finalize/2`. `@fallback_choices` stay generic — accepted degradation: a double Celeris failure is already the exceptional last resort, the generic options remain valid votes, and level-parameterized canned choices would add a fragment-coupled text table for marginal value. Recorded, not silent.
- **D-08 (option dedup):** `choices/1` gains a mechanical dedup — `Enum.uniq/1` on the kept options and a backfill that excludes already-kept strings (`@fallback_choices -- kept`) — closing Pitfall 5's minimum at one line of mechanism. No semantic validation beyond that.
- **D-09 (above L5 — clamp, raw counter keeps counting):** `absurdity_level` itself increments without ceiling (a truthful monotonic counter); only the fragment lookup clamps to L5. Issue #9 touchpoint: its 6-locks-before-the-minute-4-finale arithmetic means lock 6 lands level 6 → the prompt renders the L5 fragment (clamp is the conservative call; finale mode is #9's scope and can read the raw level when it lands). The user-prompt label renders the clamped level so label and fragment always agree.
- **D-10 (persistence):** None. The level is in-memory episode state like `beat`, `votes`, and `last_frame_url`; nothing reads persisted state at runtime today and restart recovery has been out of scope in both prior sprints. Third sprint running — reconfirmed.

## Claude's discretion

- Fragment prose wording (exact strings in Plan II, executor may polish phrasing but not weaken size classes or drop the protagonist-interaction clause — each fragment states the pot's size AND how the protagonist works it, per Pitfall 2's "prose agreeing with pixels").
- Label spellings: `ESCALATION (Ln):` in the user prompt (UPPERCASE labeled-line convention), `Escalation:` in video prompts (matches the `Style:` suffix register).
- `finalize/2` takes the bare level integer, not the whole ctx — the narrowest interface that keeps `finalize` a pure output transform.
- Test fixture levels: `celeris_test.exs` `@ctx` gains `absurdity_level: 2` (mid-ladder, distinguishes L0 defaults from real lookups); `pipeline_test.exs` `ctx()` gains `absurdity_level: 1`.
- EL-10 parametrizes emitted-prompt assertions over all six levels 0..5 in one test loop (FalMock is cheap; "fragment present at each level" is the issue's literal acceptance criterion).

## Deferred ideas

- FLF `end_image_url` keyframe escalation (render the next size class as a still, interpolate toward it) → future, the named upgrade path if prose-only escalation underdelivers in live smokes (already deferred once, STATE.md)
- VLM frame check for pot-scale regression (majority-of-3) → future, only if drift shows up live
- Premise-specific fragment sets via seed attrs (Amaka's Cooking Contest) → issue #11
- Ladder-aware `@fallback_choices` → future, if double-failure beats prove visible in practice (D-07)
- Level persistence / restart recovery → out of scope, third sprint running (D-10)
- Finale mode, intermission, episode clock → issue #9; style presets → issue #10
- Negative prompts against shrinkage → rejected (not portable across engines; naming "small pot" backfires)

## Canonical references

- `.jira/sprints/2026-09-02-escalation-engine-pot-grows/research-codebase.md` — every path:line anchor executors need (read before touching anything); cites pinned to `gen/speakless` HEAD cb99238.
- `.jira/sprints/2026-09-02-frame-chained-continuity/CONTEXT.md` — the prior pinned ctx contract this sprint amends (D-03 above); all its other interfaces remain binding.
- `.jira/STATE.md` — cross-sprint decisions D-01..D-16 + frame-chaining decisions, all binding.
- `PLOT.md` §5 — the three choice conditions escalation-form options must preserve.
- `SPEAKLESS-ADHERENCE.md` / `git show gen/wordless:WORDLESS-ADHERENCE.md` — the adherence evidence behind mechanical enforcement and one-fragment-per-surface.
- `server/AGENTS.md:69-78` — binding test rules: `start_supervised!`, no `Process.sleep`, sync via `:sys.get_state`, tests drive every timeline event manually.
- Executor environment: run inside `nix develop` from the repo root; Postgres on port 57432 must be up; tests via `mix test` from `server/`.
