---
sprint: 2026-09-02-escalation-engine-pot-grows
plan: III
wave: III
goal: EpisodeServer owns absurdity_level (init 0, +1 per canonized lock only, clobber-proof) exposed via the pipeline ctx; L0–L5 ladder fragments render as an ESCALATION line in the Celeris user prompt and a mechanical Escalation append on every outgoing video prompt (scene, bridge, fallback, segments, opening still); vote options are escalation-form per system-prompt rules with a mechanical dedup — proven by all 11 EL- predicates sensed and mix test exiting 0.
worktree: false
branch: jira/2026-09-02-escalation-engine-pot-grows
issue: 8
depends_on: [I, II]
parallel_with: []
files_modified:
  - server/lib/whn/pipeline.ex
  - server/test/whn/pipeline_test.exs
covers:
  - D-05
  - "GOAL: hermetic tests — ladder fragment present in the emitted prompt at each level (fal surface)"
  - "GOAL: escalation baked into pixels self-persists — the opening still anchors L0, bridges and segments carry the level's prose"
  - "RESEARCH: run_segments reuses the scene prompt for all 3 segments, so injected prose rides into every segment; the opening flux prompt is built from ctx at pipeline.ex:90-92"
  - "RESEARCH: emitted-prompt assertions via FalMock-captured i2v/flux args (pipeline_test house pattern)"
effects:
  - EL-10
  - EL-11
---

# Plan III: The emitted surfaces — opening anchor and per-level fal-prompt proof

**Sprint goal:** see frontmatter `goal:`.
**This plan delivers:** the L0 fragment baked into the opening flux still (the first conditioning image of the whole pixel chain) and the end-to-end proof that every prompt actually reaching the video model — bridge and all three segments — carries the ctx level's fragment, at every ladder level. Depends on Plan II (`escalation_fragment/1`, `finalize/2`) and Plan I (ctx key).

**Environment:** run inside `nix develop` from the repo root; Postgres on 57432 up; tests via `mix test` from `/home/drew/kit/whn/server`. `pipeline_test.exs` needs `ffmpeg` on PATH (the devshell provides it).

## Tasks

### I. Opening flux prompt carries the fragment

- **Files:** `server/lib/whn/pipeline.ex`
- **Read first:** `server/lib/whn/pipeline.ex` (`run_opening/2`, `opening_prompt/1` at lines 90–92), `server/lib/whn/prompts.ex` (the Plan II accessor), `CONTEXT.md` D-05.3
- **Action:** Per D-05.3, change `opening_prompt/1` to render the ctx level's fragment between the premise and the style suffix:

  ```elixir
  defp opening_prompt(ctx) do
    "Opening frame: #{ctx.episode.premise} Escalation: #{Whn.Prompts.escalation_fragment(ctx.absurdity_level)} #{Whn.Prompts.vertical_suffix()}"
  end
  ```

  `ctx.absurdity_level` is 0 at the opening (init value; the opening never passes through a lock), so this is the L0 anchor — but keying off the ctx (not a literal 0) keeps the function honest if an opening ever runs mid-ladder. No other pipeline change: bridge and segment prompts already carry the fragment via `finalize/2` (Plan II), and `run_segments/5` reuses the scene prompt for all three segments.
- **Done when:** `grep -n "escalation_fragment" server/lib/whn/pipeline.ex` matches exactly once, inside `opening_prompt/1`; `mix compile --warnings-as-errors` succeeds.
- **Covers:** D-05.3, GOAL: opening still anchors L0

### II. Emitted-prompt tests at every level

- **Files:** `server/test/whn/pipeline_test.exs`
- **Read first:** `server/test/whn/pipeline_test.exs` (whole file — setup's FalMock/Req.Test wiring, the `ctx/1` helper, the existing FalMock-captured prompt assertions at 168–216 and the drain-on-exit discipline), `server/test/support/fal_mock.ex`, `features/ladder-prompts.feature`, `server/AGENTS.md:69-78`
- **Action:** Two additive tests, each with its `# EL-xx` predicate comment:
  - **EL-10** "emitted video prompts carry the level's fragment at every ladder level": for each `level <- 0..5`, run `Whn.Pipeline.start_cycle(self(), ctx(%{absurdity_level: level, last_frame_url: "mock://prev.jpg"}))`, receive the pinned message sequence through `{:last_frame, _}` (existing house pattern — `assert_receive` with the 10_000 timeout, no sleeps), then from `Whn.FalMock.calls()` collect every `{:i2v, args}` prompt for that run and assert each one (1 bridge + 3 segments) contains `Whn.Prompts.escalation_fragment(level)`. Reset or diff the mock's call log between levels (use the existing calls-snapshot idiom; a fresh count-based slice is fine). Also assert the clamp end-to-end once: a run at `absurdity_level: 7` emits prompts containing `escalation_fragment(5)`.
  - **EL-11** "the opening still is the L0 anchor": `Whn.Pipeline.start_opening(self(), ctx(%{beat: 0, winning_choice: nil, last_frame_url: nil, absurdity_level: 0}))`, receive through the opening's message sequence, then assert the captured `{:flux, args}` prompt contains `"Escalation: " <> Whn.Prompts.escalation_fragment(0)` and still contains `Whn.Prompts.vertical_suffix()`.
  If the 6-level loop in one test proves slow against the shared ffmpeg fixture, keep it as one test but reuse a single fixture — do NOT reduce the level coverage: "fragment present in the emitted prompt at each level" is issue #8's literal acceptance criterion.
- **Done when:** `grep -n "EL-10\|EL-11" server/test/whn/pipeline_test.exs` matches both; `mix test test/whn/pipeline_test.exs` exits 0; full `mix test` exits 0.
- **Covers:** EL-10, EL-11, GOAL: fragment present in the emitted prompt at each level

## Nyquist criteria for this plan

- [ ] `mix test test/whn/pipeline_test.exs` exits 0 with EL-10 (all six levels + clamp case) and EL-11 sensed
- [ ] Full `mix test` exits 0 — the sprint's complete suite, all 11 EL- predicates now sensed across the three test files
- [ ] `grep -rn "absurdity_level" server/lib/` shows exactly the contracted sites: episode_server (3), prompts (user-prompt line), celeris (finalize call sites), pipeline (opening_prompt)
- [ ] `git status --porcelain web/` prints nothing
- [ ] `npx`-style lint equivalents: `mix compile --warnings-as-errors` clean (no formatter drift: `mix format --check-formatted`)

## Risks accepted in this plan

- Mock-verified only: whether the L0 pot actually renders in the flux still and whether size classes land in pixels awaits a live production smoke (same posture as the frame chain last sprint; FLF keyframes are the deferred upgrade path).
- The t2v fallback bridge (frame extraction failed upstream) carries the fragment as its only escalation carrier — accepted degradation per existing repo posture (Pitfall 3); no extra handling.
- Opening incongruity until #11: the L0 pot fragment rides into the Salary Just Entered opening frame — known, recorded in CONTEXT.md.
