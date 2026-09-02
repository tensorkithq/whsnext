# Brief: 2026-09-02-escalation-engine-pot-grows

**Created:** 2026-09-02
**Source:** github-issue:8
**Issue:** https://github.com/tensorkithq/whn/issues/8

## Statement

Escalation engine: The Pot Grows — server-owned absurdity ladder, one size class per vote.

The show's new creative engine: visual tension through consistent absurdity instead of dialogue-driven story. One focal object (the pot) grows exactly one size class at every vote lock — monotonic, never shrinks — until the finale.

Design, from the research (agent report, 2026-09-02, user-selected over 4 alternatives):

- The server owns an integer `absurdity_level`, bumped mechanically at each vote lock — never trusted to the script engine (both adherence logs show instruction-following is probabilistic).
- Each level indexes a fixed ladder of Environment/Action prompt fragments (e.g. L2: "the pot stands chest-high; she stirs from a stool with a paddle"), injected into the Celeris user prompt and echoed into the sectioned video_prompt.
- Reliability property this design leans on: escalation baked into pixels self-persists — frame-chained i2v carries the big pot whether or not the model reads prose.
- Votes never decide *whether* things escalate — they pick the escalation's visible form ("stir with: canoe paddle / palm trunk / climb in and stomp"), keeping options understandable, debatable, and visually consequential (PLOT.md §5).

### Acceptance criteria (from the issue)

- [ ] `absurdity_level` lives in EpisodeServer state, +1 at each canonized lock, exposed to the pipeline ctx
- [ ] Ladder fragments (L0–L5) injected into the script-engine prompt and constrained into the video_prompt Environment/Action sections
- [ ] Vote options generated as escalation-form choices; below-quorum revotes do NOT bump the level
- [ ] Hermetic tests: level bump on lock, no bump on revote, ladder fragment present in the emitted prompt at each level

### Open questions (from the issue)

- Mirror the level into story_state for script-engine visibility, or keep it purely ladder-indexed server-side?

Refs #7 (audio direction), the SPEAKLESS/WORDLESS adherence logs on gen/speakless and gen/wordless.

## Constraints

- Server owns the level; the script engine never controls whether escalation happens (labels: enhancement)
- Level bumps are monotonic — +1 per canonized lock only; below-quorum revotes never bump
- Binding cross-sprint decisions D-01..D-16 plus the frame-chaining decisions in .jira/STATE.md
- Related issues filed the same day shape adjacent scope: #9 (5-minute format / finale), #10 (style presets), #11 (plot catalog / Amaka's Cooking Contest seed — the premise this ladder narrates)

## Out of scope

- Finale mode, intermission, and episode clock (#9)
- Style presets / per-episode style suffix (#10)
- Seeding Amaka's Cooking Contest and the README plot catalog (#11) — though the ladder design should not preclude premise-specific fragment sets
