# Wordless adherence: which prompt format keeps H3 Max characters from speaking?

The show is wordless, but MiniMax H3 Max still gives characters spoken
pseudo-language ("babble") when a scene tempts it. This experiment compares
eight audio-clause formats on one fixed, maximally speech-tempting scenario,
measures speech with Whisper transcription, and ships the winner as the new
`@vertical_suffix` in `server/lib/whn/prompts.ex`.

## Method

- Model: `minimax/h3-max/text-to-video` via the fal queue API.
  `{prompt_expansion_mode: "balanced", duration: 10, resolution: "480P",
  aspect_ratio: "9:16", seed: fixed}` — the pipeline's exact t2v shape.
- Fixed scenario, identical across variants (only the audio clause varies):

  > A heated doorway confrontation in a Lagos apartment block: a young man
  > argues with his landlord in the doorway, both animated and gesturing
  > wildly, jabbing fingers, throwing hands up, faces contorted in outrage as
  > the argument escalates.

  followed by the branch's style clause ("Vertical 9:16 vibrant 2D cartoon
  animation: bold clean outlines, flat saturated colors, warm Lagos palette,
  expressive exaggerated characters, smooth motion; any incidental signage in
  English.").
- Round 1: all 8 variants at seed 424242. Round 2: the two best at seed
  910910, plus the combined variant at the same seed with the last clip of
  budget. 11 clips total.
- Measure: `fal-ai/whisper` (task: transcribe) on each clip's video URL;
  score = transcribed word count. Empty or filler-only (non-lexical
  exclamations like "Woo!") counts as perfect.

## Variants (audio clause only; everything else identical)

| # | Format | Clause |
|---|--------|--------|
| v1 | Baseline (branch suffix) | "all voices are wordless — no spoken dialogue, no chatter, mouths busy with expression not words." (trailing) |
| v2 | Blunt negatives | "No dialogue, no speech, no talking, no voices, silent characters." (trailing) |
| v3 | Positive audio spec | "Audio: instrumental score and street ambience only; the characters mime — gestures and facial expression carry everything." |
| v4 | Silent-film framing | "In the style of a silent-film pantomime: no vocal audio at all, expressive exaggerated gesture." |
| v5 | Front-loaded | baseline's audio clause as the FIRST sentence instead of trailing |
| v6 | Reference clause | "Sound: ambient environmental audio and cinematic score only; any voices are wordless (humming, gasps, laughter without words) — no spoken dialogue." |
| v7 | Scene-design avoidance | scenario rewritten so mouths are occupied (landlord arms folded jaw clenched, man biting his lip) + v6's clause |
| v8 | Combined | front-load + silent-film + blunt negatives + positive spec in one leading block |

Baseline caveat: as sent, v1 carried a stray period before the semicolon
("…signage in English.; all voices…") — a harness artifact; the wording is
otherwise the branch suffix verbatim.

## Results

Transcripts verbatim (Whisper, leading whitespace trimmed; the v1 scream run
is elided for length):

- **v1** seed 424242 — 10 words: "Lasi, Adam, kuzi goji mo siya Botabo
  Swans! Huuu! AHHHH…hhh…vvv" (long scream run elided)
- **v2** seed 424242 — 1 word, filler-only: "Boop."
- **v2** seed 910910 — 9 words: "హాము పపకేతింబ్లా భాయ్యే తో పప్తేన దాల్దేన
  దాల్దేయాతో అలు కూడా"
- **v3** seed 424242 — 17 words: "Dostim tu fut. Huuu! Domi niska do sele tu
  skenan. E poso fatakwansi sam sakulo ven segan."
- **v4** seed 424242 — 0 words: "" (empty)
- **v4** seed 910910 — 17 words: "Akoyo komo keto so pase? Ma, myo djoto
  komproto roji! Mo poji keto chodi proto proto mama!"
- **v5** seed 424242 — 3 words, filler-only: "র่ा! র่! র่!" (transcribed
  shouts, no lexical content)
- **v6** seed 424242 — 13 words: "Basme, I done the goat for lease on and of
  wadu. Huuu! Huuu!"
- **v7** seed 424242 — 4 words: "Ray, amdu kubi folit?"
- **v8** seed 424242 — 3 words, filler-only: "Woo! Woo! Woo!"
- **v8** seed 910910 — 33 words: "Gata ya pomba kopa e se panike e me doazi E
  di pati gebera du sa prezonti Agon, asi kol ya te debate a kia subaku bela
  E non su ki zoman se"

### Ranking (word counts per run; lexical words in parentheses where filler inflates the count)

| Rank | Variant | Seed 424242 | Seed 910910 | Total (lexical) |
|------|---------|-------------|-------------|-----------------|
| 1 | v2 blunt negatives | 1 (0) | 9 | 10 (9) |
| 2 | v4 silent-film | 0 | 17 | 17 (17) |
| 3 | v8 combined | 3 (0) | 33 | 36 (33) |
| — | v5 front-loaded | 3 (0) | not rerun | 3 (0), n=1 |
| — | v7 scene-design | 4 | not rerun | 4, n=1 |
| — | v1 baseline | 10 | not rerun | 10, n=1 |
| — | v6 reference clause | 13 | not rerun | 13, n=1 |
| — | v3 positive spec | 17 | not rerun | 17, n=1 |

## Findings

1. **The branch's suffix fails under temptation.** On the friendly seed the
   baseline produced 10 words of babble while four other formats produced
   zero lexical words. "All voices are wordless" phrasing (baseline and the
   reference clause, v6) ranked near the bottom.
2. **No wording is seed-proof.** Seed 910910 defeated every variant tested on
   it (9, 17, and 33 words). Prompt format shifts the distribution; it does
   not close the tap. Truly guaranteed silence needs a post-generation gate
   (transcribe-and-retry) or muxing out the vocal stem — out of scope here.
3. **Blunt stacked negatives degrade least.** v2 was filler-only on seed 1
   and had the lowest count on the hostile seed — best total by a wide
   margin among the three stability-tested formats.
4. **More words ≠ more suppression.** The kitchen-sink combination (v8) had
   the worst hostile-seed result (33), worse than any of its ingredients
   alone. Front-loading alone (v5) looked good (filler-only) but was not
   stability-tested.
5. **No visual regressions.** Frame strips of v2/v4/v5/v8 all keep the
   vibrant 2D cartoon look and the doorway confrontation reads clearly —
   the silent-film framing did not push the model to black-and-white.

## Recommendation (shipped)

Replace the audio clause of `@vertical_suffix` with v2's blunt negatives,
exactly as tested:

> Vertical 9:16 vibrant 2D cartoon animation: bold clean outlines, flat
> saturated colors, warm Lagos palette, expressive exaggerated characters,
> smooth motion; any incidental signage in English. No dialogue, no speech,
> no talking, no voices, silent characters.

The winning format is trailing, like today's suffix, so no pipeline change
is needed and the system prompt's Sound bullet (which governs the script
engine, not the video model) stays as is.

Cost: 11 clips at 480P/10s plus 11 Whisper transcriptions, ~$5.50.
