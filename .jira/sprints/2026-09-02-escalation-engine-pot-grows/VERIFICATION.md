---
sprint: 2026-09-02-escalation-engine-pot-grows
verified_at: 2026-09-02T23:20:00Z
verdict: PASS
---

# Verification: 2026-09-02-escalation-engine-pot-grows

Goal-backward audit of the executed sprint. Asks: "does the codebase, as it stands now, deliver what the goal promised?" — distinct from `jira-nyquist` (which asks "do tests cover the criteria?") and `jira-reviewer` (which audits the diff).

## Goal

EpisodeServer owns `absurdity_level` (init 0, +1 per canonized lock only, clobber-proof) exposed via the pipeline ctx; L0–L5 ladder fragments render as an ESCALATION line in the Celeris user prompt and a mechanical Escalation append on every outgoing video prompt (scene, bridge, fallback, segments, opening still); vote options are escalation-form per system-prompt rules with a mechanical dedup — proven by all 11 EL- predicates sensed and `mix test` exiting 0. (Shared frontmatter goal of 01/02/03-PLAN.md; restates issue #8's four acceptance criteria per D-00.)

## Goal decomposition

- [x] Outcome 1: `absurdity_level` lives in EpisodeServer state, +1 at each canonized lock only, exposed to the pipeline ctx, clobber-proof against `story_state_updates`
- [x] Outcome 2: Ladder fragments (L0–L5) injected into the script-engine prompt and mechanically constrained into every outgoing video prompt (bridge, scene, segments, fallback, opening still), before the Style suffix
- [x] Outcome 3: Vote options generated as escalation-form choices (system-prompt rules + mechanical dedup); below-quorum closes and revotes never bump the level
- [x] Outcome 4: Hermetic tests — level bump on lock, no bump on revote, ladder fragment present in the emitted prompt at each level; `mix test` exits 0

## Findings

### Outcome 1: server-owned level, bump only at canonized lock, ctx exposure, clobber-proof

- **Status:** delivered
- **Evidence:**
  - `source-audit` — `server/lib/whn/episode_server.ex:61` (`absurdity_level: 0` in the `init/1` state map beside `beat`); `:233` (the sole `+1`, inside `lock_and_start_cycle/2` next to the beat bump); `:443` (key in `pipeline_ctx/2`). `grep -rn "absurdity_level" server/lib/` returns exactly these three ownership sites plus the four read sites (prompts:135, celeris:39/43/44, pipeline:92) — no bump anywhere else.
  - `source-audit` — the below-quorum branch (`episode_server.ex:185-190`) and the `:revote`/`:vote_close` handlers (`:199-215`) never touch the level; the only path to `lock_and_start_cycle/2` is the quorum branch at `:181-183`.
  - `source-audit` — clobber-proofing: the model-controlled merge at `episode_server.ex:257-258` writes only into `state.story_state`; `absurdity_level` is a sibling top-level key the merge cannot reach. Never mirrored into `story_state` (D-02).
  - `command` — strict ctx access per D-03: a ctx missing the key crashes. `mix run -e` probe: `Whn.Prompts.user_prompt(Map.delete(ctx, :absurdity_level))` raises `KeyError` (observed `:crashed`); all readers use dot access, no `Map.get` default.
  - `source-audit` — parked-cycle refresh at `episode_server.ex:150` refreshes only `last_frame_url`; the ctx snapshot at `:237` is taken post-bump, so a held cycle carries the correct level (D-03).

### Outcome 2: ladder fragments on every prompt surface

- **Status:** delivered
- **Evidence:**
  - `source-audit` — 6-element `@ladder` at `server/lib/whn/prompts.ex:44-51` (each fragment states the pot's size AND how the protagonist works it); single accessor `escalation_fragment/1` at `:54-55` with the `min(level, 5)` clamp.
  - `source-audit` — Celeris user prompt: `ESCALATION (L…):` line at `prompts.ex:135`, directly after STORY STATE, label clamped to match the fragment (D-09).
  - `source-audit` — mechanical video-prompt append: `Celeris.finalize/2` at `celeris.ex:244-254` applies `strip_dialogue`/`clamp_dialogue` → `escalation/2` (`"\nEscalation: " <> fragment`, `:256-257`) → `suffix/1` (`"\nStyle: " <> vertical_suffix`, `:259`) — fragment after dialogue handling, before the terminal Style suffix, exactly D-05.2's ordering. All three `run/1` call sites pass `ctx.absurdity_level` (`celeris.ex:39,43,44`); the fallback flows through the same `finalize` at `:44`, so the canned beat carries the fragment (D-07). Segments inherit it via the shared `next_scene.video_prompt` (`pipeline.ex:112-127`).
  - `source-audit` — opening flux still: `opening_prompt/1` at `pipeline.ex:90-94` renders `"Escalation: " <> escalation_fragment(ctx.absurdity_level)` between premise and style suffix — the L0 anchor (D-05.3).
  - `command` — clamp behavior observed live via `mix run -e`: `escalation_fragment(7) == escalation_fragment(5)` → `true`; label at level 9 renders `ESCALATION (L5):` with the L5 fragment.
  - `command` — end-to-end emitted-prompt proof: `nix develop --command bash -c "cd server && mix test"` → **64 tests, 0 failures** (Postgres 57432 accepting connections); includes the EL-10 loop asserting all 4 captured i2v prompts carry the level's fragment at every level 0..5 plus a clamp run at 7 (`pipeline_test.exs:285-297`), and EL-11 asserting the captured flux prompt carries `"Escalation: " <> fragment(0)` plus the vertical suffix (`:299-320`).

### Outcome 3: escalation-form vote options; revotes never bump

- **Status:** delivered
- **Evidence:**
  - `source-audit` — system prompt: ESCALATION rules bullet at `prompts.ex:29` ("It is story truth … You do not decide whether escalation happens"); rewritten `next_choices` bullet at `:27` ("exactly 3 distinct ways the protagonist could visibly handle the situation at its current scale — three forms of the same next beat, never whether the story escalates", PLOT.md §5 conditions preserved, "no duplicates") — matches D-06.
  - `source-audit` — mechanical dedup at `celeris.ex:195-206`: `Enum.uniq()` on kept options plus backfill `@fallback_choices -- kept` that cannot reintroduce an echoed fallback string (D-08). `@fallback_choices` remain generic per D-07 (recorded degradation).
  - `source-audit` — no-bump-on-revote: same evidence as Outcome 1; the `:revote` handler re-enters `vote_open` (`episode_server.ex:206-213`), which never touches the level; asserted by the revote-then-quorum test expecting ctx level 1, not 2 (`episode_server_test.exs:150-175`).

### Outcome 4: hermetic tests green

- **Status:** delivered
- **Evidence:**
  - `command` — `nix develop --command bash -c "cd server && mix test"` (Postgres 57432 up): `64 tests, 0 failures`. Matches EXECUTION.md's claim including the two nyquist gap-fill commits (f27a201 exactly-one-Escalation-line pin, 9b6344f echoed-fallback backfill).
  - `command` — `mix compile --warnings-as-errors` and `mix format --check-formatted` both clean (run in the same nix shell).
  - `source-audit` — the tests are hermetic and follow `server/AGENTS.md` rules: `assert_receive` with explicit timeouts, `:sys.get_state` sync, manually driven `{:timeline, …}` events, no `Process.sleep` (`episode_server_test.exs`, `celeris_test.exs`, `pipeline_test.exs`).

### Scope guards

- **Zero web/ changes:** `command` — `git status --porcelain web/` empty; `git diff --stat gen/speakless...HEAD` touches exactly 7 files, all under `server/` (celeris.ex, episode_server.ex, pipeline.ex, prompts.ex + their three test files).
- **No creep into #9/#10/#11:** `command` — added-lines grep for `finale|intermission|episode clock|style preset|seed attr|amaka` over the branch diff: no matches. The ladder is premise-neutral ("the protagonist") behind a single accessor, so #11's fragment sets remain possible without being started.
- **Ctx contract matches D-03 exactly:** `source-audit` — `pipeline_ctx/2` at `episode_server.ex:434-445` builds `%{beat, seed, episode: %{title, premise}, story_state, winning_choice, last_frame_url, history, absurdity_level}` — the prior pinned shape plus exactly the one new key, required (strict access verified by the KeyError probe above).

## Source coverage

| Decision | Plan | Implemented | Evidence |
|----------|------|-------------|----------|
| D-00 (goal restatement) | all | yes | this report; suite 64/64 green |
| D-01 (base branch) | orchestration | yes | command: branch `jira/2026-09-02-escalation-engine-pot-grows`, `git log` shows lineage off `gen/speakless` (cb99238 in history) |
| D-02 (server-owned level, no story_state mirror) | 01-PLAN task I | yes | source-audit: `episode_server.ex:61,233,443`; level absent from the `:257-258` merge |
| D-03 (ctx-contract amendment, strict access) | 01-PLAN task I | yes | source-audit: `episode_server.ex:434-445`; command: KeyError probe crashed on missing key |
| D-04 (ladder home and shape) | 02-PLAN task I | yes | source-audit: `prompts.ex:44-55` — `@ladder` (6 elements) + `escalation_fragment/1` sole lookup point |
| D-05 (labeled appends, three surfaces) | 02-PLAN task II / 03-PLAN task I | yes | source-audit: `prompts.ex:135` (user prompt), `celeris.ex:244-259` (finalize ordering), `pipeline.ex:90-94` (opening) |
| D-06 (escalation-form options rules) | 02-PLAN task I | yes | source-audit: `prompts.ex:27,29` |
| D-07 (fallback posture) | 02-PLAN task II | yes | source-audit: `celeris.ex:44` fallback through finalize; `@fallback_choices` at `:23-27` unchanged/generic |
| D-08 (option dedup) | 02-PLAN task II | yes | source-audit: `celeris.ex:195-206` — `Enum.uniq` + `@fallback_choices -- kept` backfill |
| D-09 (clamp at L5, raw counter uncapped) | 01/02-PLAN | yes | source-audit: `episode_server.ex:233` no ceiling; `prompts.ex:55,135` clamped lookup and label; command: `fragment(7) == fragment(5)` observed true |
| D-10 (no persistence) | 01-PLAN | yes | source-audit: `grep absurdity_level server/lib/` shows no Store/persistence site; level is in-memory state only |

## Predicate coverage

All 11 EL- predicates are machine-sensed by the suite; the full suite was re-run for this verification (64/64 green).

| @req | Claimed by plan | Sensed | Evidence |
|------|-----------------|--------|----------|
| EL-01 | 01-PLAN | yes — suite | command: `episode_server_test.exs:71-73` (ctx and state level == 1 after quorum lock) |
| EL-02 | 01-PLAN | yes — suite | command: `episode_server_test.exs:145-147` (below-quorum stays 0) + `:173-174` (revote round-trip → 1, not 2) |
| EL-03 | 01-PLAN | yes — suite | command: `episode_server_test.exs:190-209` (`story_state_updates: %{"absurdity_level" => 99}` ignored) |
| EL-04 | 02-PLAN | yes — suite | command: `celeris_test.exs:275-278` (labeled ESCALATION (L2) line) |
| EL-05 | 02-PLAN | yes — suite | command: `celeris_test.exs:280-309` (both video prompts, exactly one Escalation line, before suffix, survives clamping) |
| EL-06 | 02-PLAN | yes — suite | command: `celeris_test.exs:311-320` (fallback beat carries the line) |
| EL-07 | 02-PLAN | yes — suite | command: `celeris_test.exs:322-326`; also observed live via mix run probe |
| EL-08 | 02-PLAN | yes — suite | command: `celeris_test.exs:328-336` (system-prompt content assertions) |
| EL-09 | 02-PLAN | yes — suite | command: `celeris_test.exs:338-376` (dedup + echoed-fallback backfill branch) |
| EL-10 | 03-PLAN | yes — suite | command: `pipeline_test.exs:285-297` (all 4 i2v prompts at levels 0..5 + clamp run at 7) |
| EL-11 | 03-PLAN | yes — suite | command: `pipeline_test.exs:299-320` (flux prompt carries `Escalation: ` + L0 fragment + suffix) |

No unclaimed and no unsensed predicates.

## Verdict

**PASS** — all 4 decomposed outcomes delivered, all 11 locked decisions (D-00..D-10) implemented, all 11 EL- predicates sensed, suite 64/64 green, zero `web/` changes, no scope creep into issues #9/#10/#11.

Caveat carried from the phase boundary (not a gap): escalation landing *in pixels* is probabilistic by design — this sprint is verified hermetically; live visual fidelity awaits a production smoke (warden/human).

## Next steps

None required for this sprint. Post-merge: a production smoke to confirm the frame-chained pot growth reads on screen (already noted in CONTEXT.md's phase boundary and the deferred FLF keyframe path).
