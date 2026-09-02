# Speakless Adherence: single scripted line, one speaker, nothing else

Empirical test of which prompt format makes MiniMax H3 Max speak exactly one
short scripted English line from one character mid-clip — nothing before,
nothing after, no second voice. Eleven live clips were generated and
transcribed; the winning format ships in `server/lib/whn/prompts.ex`.

## Method

- Model: `minimax/h3-max/text-to-video` via the fal queue API.
  Body: `{prompt, prompt_expansion_mode: "balanced", duration: 10,
  resolution: "480P", aspect_ratio: "9:16", seed}`.
- Fixed scenario for every variant: a Lagos apartment doorway, a young man
  and his landlord both agitated over rent. The only scripted line, spoken
  by the man: **"Not today sir, I will pay you next week."**
- Fixed 2D-cartoon style suffix (the production suffix, verbatim) on every
  variant, so only the dialogue formatting/control changed.
- Seeds: round 1 = 4242 for all variants; round 2 rerun = 8888.
- Measurement: each clip's audio transcribed with `fal-ai/whisper`
  (`task: "transcribe"`). Two scores per clip, computed by longest-common-
  subsequence alignment of normalized words (lowercased, punctuation
  stripped):
  - **Fidelity** — fraction of the scripted words present in order
    (perfect = 1.0).
  - **Leakage** — count of transcript words that are not part of the
    scripted line (perfect = 0).

## Variants

Only the dialogue segment changed; scene prose and style suffix were
byte-identical across v1–v8. v9 restructured the whole prompt into labeled
sections.

| # | Name | Dialogue formatting under test |
|---|------|-------------------------------|
| v1 | baseline | Production pipeline emission, built by running the real `clamp_dialogue`: inline `says: "…"` + injected `The speaker then falls silent.` + post-line silence prose + suffix clause |
| v2 | negatives | Line + `No other dialogue, no other speech, no other voices; only this one line is spoken.` |
| v3 | attribution | `The man speaks exactly one line: "…"` |
| v4 | screenplay | `MAN: "…"` |
| v5 | timing | `At the midpoint of the shot, the man says his only words: "…" Before and after, no one speaks.` |
| v6 | sandwich | `Silence. Then the man says: "…" Silence returns; mouths stay closed.` |
| v7 | muzzle | Landlord explicitly described as listening jaw clenched, arms folded, saying nothing + baseline line format |
| v8 | combined | Muzzle + midpoint timing + one short negative clause |
| v9 | sectioned | Labeled sections — `Camera:` / `Environment:` / `Action:` / `Dialogue (the only spoken words in the clip): MAN: "…"` / `Style:` — dialogue as its own block outside the scene prose |

## Results

Every whisper transcript, verbatim (leading space as returned):

```
" Not today, sir. I will pay you next week."
```

All eleven clips returned that identical transcript.

| Variant | Seed | Fidelity | Leakage |
|---------|------|----------|---------|
| v1 baseline | 4242 | 1.0 | 0 |
| v2 negatives | 4242 | 1.0 | 0 |
| v3 attribution | 4242 | 1.0 | 0 |
| v4 screenplay | 4242 | 1.0 | 0 |
| v5 timing | 4242 | 1.0 | 0 |
| v6 sandwich | 4242 | 1.0 | 0 |
| v7 muzzle | 4242 | 1.0 | 0 |
| v8 combined | 4242 | 1.0 | 0 |
| v9 sectioned | 4242 | 1.0 | 0 |
| v1 baseline | 8888 | 1.0 | 0 |
| v9 sectioned | 8888 | 1.0 | 0 |

## Ranking and winner

Round 1 was a nine-way perfect tie. Round 2 re-ran the incumbent (v1) and
the pre-registered favored design (v9, sectioned) on a second seed — both
perfect again. With adherence saturated, the tie broke on design grounds:
the sectioned format ships. It ties the best measured result on both seeds
while giving the script engine a structurally checkable shape — the spoken
line lives in its own labeled block instead of being fished out of scene
prose, and the label itself ("the only spoken words in the clip") carries
the constraint that previously needed injected silence-marker prose.

## Findings

1. On this scenario, H3 Max honored a quoted scripted line under every
   format tried: no pre-line chatter, no post-line improvisation, no second
   voice, across two seeds. Adherence did not differentiate the formats.
2. The word-for-word transcript stability (identical across eleven clips)
   suggests the model treats a clearly quoted line as ground truth; the
   surrounding control prose (negatives, timing, silence sandwiches,
   muzzles) neither helped nor hurt here.
3. A dialogue-heavy two-party standoff is exactly the setup where earlier
   builds saw improvised speech, so the saturation is meaningful but not
   proof against regression on other scenarios — the mechanical clamp
   stays.
4. Incidental: the previous emission had a missing-space join artifact
   ("falls silent.then he says nothing more") where the injected marker met
   the trimmed remainder. The sectioned rewrite removes the injection path
   and the artifact with it.

## What shipped

- The script engine now authors `video_prompt`s as labeled sections
  (`Camera:` / `Environment:` / `Action:` / `Dialogue:`), with the one
  allowed line in its own `Dialogue (the only spoken words in the clip):`
  block, never inline in the Action prose.
- `clamp_dialogue/1` still enforces the cap mechanically (first quoted
  span only, 12 words), and now guarantees the guard label: an authored
  block keeps its label; an inline line is moved under an injected one.
- `strip_dialogue/1` also removes stray guard labels, so bridges and
  post-line segments never carry an empty `Dialogue:` block.
- The style suffix is appended as its own `Style:` section and is otherwise
  unchanged.
