---
sprint: 2026-09-02-escalation-engine-pot-grows
plan: II
wave: II
goal: EpisodeServer owns absurdity_level (init 0, +1 per canonized lock only, clobber-proof) exposed via the pipeline ctx; L0–L5 ladder fragments render as an ESCALATION line in the Celeris user prompt and a mechanical Escalation append on every outgoing video prompt (scene, bridge, fallback, segments, opening still); vote options are escalation-form per system-prompt rules with a mechanical dedup — proven by all 11 EL- predicates sensed and mix test exiting 0.
worktree: false
branch: jira/2026-09-02-escalation-engine-pot-grows
issue: 8
depends_on: [I]
parallel_with: []
files_modified:
  - server/lib/whn/prompts.ex
  - server/lib/whn/celeris.ex
  - server/test/whn/celeris_test.exs
  - server/test/whn/pipeline_test.exs
covers:
  - D-04
  - D-05
  - D-06
  - D-07
  - D-08
  - D-09
  - "GOAL: ladder fragments (L0–L5) injected into the script-engine prompt and constrained into the video_prompt"
  - "GOAL: vote options generated as escalation-form choices"
  - "GOAL: hermetic tests — ladder fragment present in the emitted prompt at each level (finalize surface)"
  - "RESEARCH: ladder as module attribute in Whn.Prompts beside its consumer, single accessor keeps #11 attrs-override possible"
  - "RESEARCH: mechanical injection at the finalize/1 seam where Style is already appended; fallback flows through finalize too"
  - "RESEARCH: single-newline labeled append survives squeeze/1; one clean fragment per surface (WORDLESS anti-stacking)"
  - "RESEARCH: dedup missing in choices/1 — duplicates survive the clamp (Pitfall 5 minimum)"
effects:
  - EL-04
  - EL-05
  - EL-06
  - EL-07
  - EL-08
  - EL-09
---

# Plan II: Ladder fragments and escalation-form options in the script-engine surfaces

**Sprint goal:** see frontmatter `goal:`.
**This plan delivers:** the L0–L5 ladder table and its clamping accessor, the ESCALATION line in the Celeris user prompt, the new system-prompt rules (escalation semantics + escalation-form choices), the mechanical `Escalation:` append in `Celeris.finalize/2` (scene, bridge, and fallback video prompts), the option dedup, and their six predicates. Depends on Plan I: `user_prompt/1` strict-reads `ctx.absurdity_level`, so real ctxs must already carry the key. This plan also adds the key to `pipeline_test.exs`'s ctx fixture — without that one line, wave II ends with a red pipeline suite.

**Environment:** run inside `nix develop` from the repo root; Postgres on 57432 up; tests via `mix test` from `/home/drew/kit/whn/server`.

## Tasks

### I. Ladder table, accessor, user-prompt line, system-prompt rules

- **Files:** `server/lib/whn/prompts.ex`
- **Read first:** `server/lib/whn/prompts.ex` (whole file — attribute conventions, `user_prompt/1` heredoc, the RULES bullets), `.jira/sprints/2026-09-02-escalation-engine-pot-grows/research-codebase.md` §3–4, `CONTEXT.md` D-04/D-05/D-06/D-09, `PLOT.md` §5
- **Action:**
  1. Per D-04, add beside the other attributes:

     ```elixir
     # The escalation ladder (issue #8): one focal object, one size class per
     # canonized vote lock. Fragments state the pot's CURRENT size and how the
     # protagonist works it — prose agreeing with the chained pixels, never
     # asking for unseen mid-clip growth. Single lookup point: premise-specific
     # sets (issue #11) can override through this accessor later.
     @ladder [
       "The focal cooking pot sits on the stove at ordinary size; the protagonist cooks standing over it.",
       "The cooking pot has grown to washbasin size; the protagonist stirs two-handed with a long wooden spoon.",
       "The pot stands chest-high; the protagonist stirs from a stool with a paddle.",
       "The pot towers head-high and dominates the kitchen; the protagonist stirs from a stepladder with a boat oar.",
       "The pot fills half the room, its rim overhead; the protagonist works from scaffolding while steam clouds the ceiling.",
       "The pot is the size of a small hut, the kitchen wall opened around it; the protagonist directs the stirring from a ladder like a site foreman."
     ]
     ```

     with the public accessor (D-09 clamp lives here, and ONLY here — the raw counter is unbounded):

     ```elixir
     @doc "Ladder fragment for the level; levels above the ladder top clamp to L5."
     def escalation_fragment(level) when is_integer(level) and level >= 0,
       do: Enum.at(@ladder, min(level, 5))
     ```

  2. Per D-05.1, in `user_prompt/1` insert one labeled line directly after the `STORY STATE:` line: `ESCALATION (L#{min(ctx.absurdity_level, 5)}): #{escalation_fragment(ctx.absurdity_level)}` (a private `escalation_line/1` helper is fine; label renders the CLAMPED level so label and fragment always agree, D-09).
  3. Per D-06, two system-prompt edits inside `@system_prompt` RULES:
     - New bullet after the CONTINUITY bullet:

       ```
       - ESCALATION: the user prompt's ESCALATION line states the focal object's current absurd scale. It is story truth: render the Environment and Action sections consistent with it, never shrink it, never explain it away, never treat it as new. You do not decide whether escalation happens — the show escalates on its own schedule; you decide only how the characters live with it.
       ```

     - Rewrite the `next_choices:` bullet to:

       ```
       - next_choices: exactly 3 distinct ways the protagonist could visibly handle the situation at its current scale — three forms of the same next beat, never whether the story escalates. Each must be immediately understandable without explanation, socially debatable (different viewers genuinely prefer different options), consequential for future scenes, relationships, resources, or problems, and visually distinct on screen. Never an obviously correct option, never an obviously stupid one, no cosmetic choices, no duplicates, no choices whose consequences evaporate.
       ```

     One clean fragment per surface — do NOT repeat the ladder text in the system prompt (WORDLESS finding 4).
- **Done when:** `grep -n "escalation_fragment\|@ladder\|ESCALATION" server/lib/whn/prompts.ex` shows the attribute, the accessor, the user-prompt line, and the two rules; `mix compile --warnings-as-errors` succeeds from `server/`.
- **Covers:** D-04, D-05.1, D-06, D-09, GOAL: fragments into the script-engine prompt; escalation-form choices

### II. Mechanical video-prompt append and option dedup

- **Files:** `server/lib/whn/celeris.ex`
- **Read first:** `server/lib/whn/celeris.ex` (whole file — `run/1`, `choices/1`, `fallback/1`, `finalize/1`, `suffix/1`), `server/lib/whn/prompts.ex` (post task I), `CONTEXT.md` D-05/D-07/D-08
- **Action:**
  1. Per D-05.2, change `finalize/1` to `finalize/2` taking the level, and update all three call sites in `run/1` to pass `ctx.absurdity_level`:

     ```elixir
     defp finalize(result, level) do
       result
       |> update_in([:bridge, :video_prompt], &(&1 |> Prompts.strip_dialogue() |> escalation(level) |> suffix()))
       |> update_in([:next_scene, :video_prompt], &(&1 |> Prompts.clamp_dialogue() |> escalation(level) |> suffix()))
     end

     defp escalation(video_prompt, level),
       do: video_prompt <> "\nEscalation: " <> Prompts.escalation_fragment(level)
     ```

     Order is load-bearing: the append sits AFTER `clamp_dialogue`/`strip_dialogue` (so the single `\n` is added post-`squeeze/1` and survives, Pitfall 6) and BEFORE `suffix/1` (existing tests pin `String.ends_with?(vp, vertical_suffix())`). The fallback path (`finalize(fallback(ctx), ctx.absurdity_level)`) makes the canned video prompts ladder-aware for free (D-07); do NOT touch `@fallback_choices` (accepted degradation, D-07).
  2. Per D-08, dedup in `choices/1`:

     ```elixir
     defp choices(raw) when is_list(raw) do
       kept =
         raw
         |> Enum.map(&str(&1, 120))
         |> Enum.reject(&(&1 == ""))
         |> Enum.uniq()
         |> Enum.take(3)

       kept ++ Enum.take(@fallback_choices -- kept, 3 - length(kept))
     end
     ```

     (`@fallback_choices -- kept` keeps the backfill from reintroducing a duplicate when the model echoed a fallback string.)
- **Done when:** `grep -n "finalize(" server/lib/whn/celeris.ex` shows only 2-arity definition and call sites; `grep -n "Enum.uniq" server/lib/whn/celeris.ex` matches in `choices/1`; `mix compile --warnings-as-errors` succeeds.
- **Covers:** D-05.2, D-07, D-08, GOAL: fragments constrained into the video_prompt

### III. Prompt-surface tests and ctx fixture updates

- **Files:** `server/test/whn/celeris_test.exs`, `server/test/whn/pipeline_test.exs`
- **Read first:** `server/test/whn/celeris_test.exs` (whole file — `@ctx`, `respond_with/1`, the suffix/dialogue tests at 137, 166–213), `server/test/whn/pipeline_test.exs:93-110` (the `ctx/1` helper only), `features/ladder-prompts.feature`, `server/AGENTS.md:69-78`
- **Action:** Fixtures first: add `absurdity_level: 2` to `@ctx` in `celeris_test.exs` and `absurdity_level: 1` to the `ctx/1` defaults map in `pipeline_test.exs` (fixture line ONLY in pipeline_test — its new tests are Plan III's). Then six additive tests in `celeris_test.exs`, each with its `# EL-xx` predicate comment:
  - **EL-04:** `Prompts.user_prompt(@ctx)` contains `"ESCALATION (L2): " <> Prompts.escalation_fragment(2)`.
  - **EL-05:** with `respond_with(Jason.encode!(@reply))` (the standard valid reply), `{:ok, result} = Celeris.run(@ctx)`; assert both `result.bridge.video_prompt` and `result.next_scene.video_prompt` contain `"\nEscalation: " <> Prompts.escalation_fragment(2)` and still `String.ends_with?(vp, Prompts.vertical_suffix())`. Repeat with a reply whose next_scene video_prompt carries a quoted dialogue line (reuse the shape of the test at 174–201): the Escalation line must survive intact with its `\n` (clamp's squeeze ran before the append).
  - **EL-06:** with the garbage-twice stub (reuse the pattern at 121–138), `{:ok, :fallback, result} = Celeris.run(@ctx)`; assert both fallback video_prompts contain `"\nEscalation: " <> Prompts.escalation_fragment(2)`.
  - **EL-07:** `assert Prompts.escalation_fragment(9) == Prompts.escalation_fragment(5)` and `Prompts.user_prompt(%{@ctx | absurdity_level: 9}) =~ "ESCALATION (L5):"`.
  - **EL-08:** on `Prompts.system_prompt()` (pattern of the test at 148–164): assert it contains `"ESCALATION"`, `"never whether the story escalates"`, `"three forms of the same next beat"`, and `"no duplicates"`.
  - **EL-09:** valid reply with `"next_choices" => ["Stir with the paddle", "Stir with the paddle", "Climb in and stomp"]`; assert `result.next_choices` has 3 elements, all distinct, containing both originals and exactly one `@fallback_choices` backfill ("Face the problem head-on").
- **Done when:** `grep -n "EL-0" server/test/whn/celeris_test.exs` shows EL-04 through EL-09; `mix test test/whn/celeris_test.exs` exits 0; full `mix test` exits 0 (proves the pipeline_test fixture line landed and integration is green).
- **Covers:** EL-04, EL-05, EL-06, EL-07, EL-08, EL-09, GOAL: fragment present in the emitted prompt (finalize surface)

## Nyquist criteria for this plan

- [ ] `mix test test/whn/celeris_test.exs` exits 0 with EL-04..EL-09 sensed
- [ ] Full `mix test` exits 0 — including `pipeline_test.exs` (fixture key) and `integration_test.exs` (real ctx via Plan I)
- [ ] Existing suffix pins hold: both video_prompts still end with `vertical_suffix()` (EL-05 ordering)
- [ ] `grep -ci "escalation" server/lib/whn/celeris.ex` ≥ 2 (helper + call sites); `grep -n "min(level, 5)" server/lib/whn/prompts.ex` matches (EL-07)
- [ ] `git status --porcelain web/` prints nothing

## Risks accepted in this plan

- Semantic "three forms of one beat" is prompt-governed, not mechanically validated — inexpressible in schema (D-06); the mechanical floor is the 3-item pin + clamp + dedup.
- `@fallback_choices` stay non-escalation-form after a double Celeris failure (D-07, accepted degradation, recorded in CONTEXT.md deferred ideas).
- The default pot ladder narrates a premise (Salary Just Entered) with no pot until issue #11 seeds Amaka's Cooking Contest — known incongruity; tests assert via the accessor, never via premise assumptions.
- Prose cannot guarantee the size bump lands in pixels (Pitfall 1) — the fragment's job is agreeing with the chained frames; FLF keyframes remain the named deferred upgrade.
- Segments 1–2 run `strip_dialogue` over the shared scene prompt, collapsing the Escalation line's newline to a space mid-prompt — same treatment the Style suffix already gets; fragment text stays intact (asserted in Plan III at the emitted surface).
