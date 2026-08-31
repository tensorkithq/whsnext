---
sprint: 2026-08-31-live-episode-mvp
plan: III
wave: II
goal: One live episode runs the full loop — a vertical scene plays, the audience votes in a server-synced 10s window, and the locked winner generates the bridge and next scene via fal — proven by passing server test suites, a timed fal spike log, migrated Postgres tables, and a production build of the web client.
worktree: false
branch: jira/2026-08-31-live-episode-mvp
issue: none
depends_on: [I]
parallel_with: [IV, V]
files_modified:
  - server/mix.exs
  - server/mix.lock
  - server/lib/whn/fal.ex
  - server/lib/whn/fal/fal_ex_impl.ex
  - server/lib/whn/frames.ex
  - server/scripts/fal_spike.exs
  - server/test/whn/frames_test.exs
  - .jira/sprints/2026-08-31-live-episode-mvp/fal-spike.log
covers:
  - D-05
  - D-06
  - D-11
  - D-16
  - "RESEARCH: fal_ex dormancy → wrap behind Whn.Fal; AGENTS.md/deps drift (no HTTP client installed); ffmpeg -sseof recipe; undocumented H3 Max latency → empirical spike; FLUX 720x1280 + hosted-URL image_url + vision-with-image unverified → spike validates"
  - "GOAL: winner generates the continuation (fal foundation)"
effects:
  - FAL-01
  - FAL-02
  - FAL-03
---

# Plan III: fal foundation — deps, Whn.Fal wrapper, frames, timed spike

**Sprint goal:** One live episode runs the full loop — scene plays, audience votes in a server-synced 10s window, winner generates the continuation via fal — proven by tests, a spike log, migrations, and a web build.
**This plan delivers:** Track 3, part A. The only modules that talk to fal or ffmpeg, plus the empirical latency numbers the README §2 timing model has been resting on unverified.

Runs inside `nix develop` (ffmpeg + `pg-start` for `mix test`; Plan I's port pins are merged). FAL_KEY comes from the shell (`.env`, sourced by the shellHook) — never committed.

## Tasks

### I. Deps + Whn.Fal wrapper

- **Files:** `server/mix.exs`, `server/mix.lock`, `server/lib/whn/fal.ex`, `server/lib/whn/fal/fal_ex_impl.ex`
- **Read first:** `server/mix.exs`, CONTEXT.md "Pinned interfaces" (`Whn.Fal` callbacks — conform exactly), `tmp/interdimensional-game/lib/fal.ts` (endpoint ids and param names), RESEARCH.md "Standard Stack" (fal_ex surface: `FalEx.subscribe/2`, `FalEx.Storage.upload/2`, FAL_KEY env config)
- **Action:** Per D-11 add `{:fal_ex, "~> 0.1.0"}` and `{:req, "~> 0.5"}` to deps; `mix deps.get`. Create `Whn.Fal`: defines the five pinned callbacks (`t2v/2`, `i2v/3`, `flux/2`, `vision/2`, `upload/1`) and public functions of the same names dispatching to `Application.get_env(:whn, :fal_impl, Whn.Fal.FalExImpl)`. Create `Whn.Fal.FalExImpl` implementing the behaviour via `FalEx.subscribe/2` against `minimax/h3-max/text-to-video`, `minimax/h3-max/image-to-video`, `fal-ai/flux-2-pro`, `openrouter/router/vision`, and `FalEx.Storage.upload` — building input maps from opts (`prompt`, `duration`, `resolution`, `aspect_ratio`, `seed`, `prompt_expansion_mode`, `image_url`, `image_size`, `model`, `system_prompt`, `image_urls`, `temperature`, `max_tokens`; omit nil keys) and normalizing responses to `{:ok, %{url: ...}}` (video/image url) / `{:ok, %{output: ...}}` (vision) / `{:error, reason}`. Check fal_ex's hexdocs for its Tesla adapter default while implementing; if it needs adapter config, add it in this module's docs and config, not globally.
- **Done when:** `(cd server && mix compile --warnings-as-errors)` exits 0; `grep -c '@callback' server/lib/whn/fal.ex` = 5; `grep 'fal_impl' server/lib/whn/fal.ex` matches (FAL-01); `grep fal_ex server/mix.exs` and `grep '"req"' server/mix.lock` match.
- **Covers:** D-11, RESEARCH fal_ex-wrapper + deps-drift findings

### II. Whn.Frames — local last-frame extraction

- **Files:** `server/lib/whn/frames.ex`, `server/test/whn/frames_test.exs`
- **Read first:** `tmp/interdimensional-game/experiments/grab-frames.mjs` (the exact ffmpeg recipe), CONTEXT.md D-06, `server/AGENTS.md` (test rules)
- **Action:** `Whn.Frames.last_frame(video_url) :: {:ok, frame_url} | {:error, term}`: `Req.get!` the mp4 to a `System.tmp_dir!()` file, run `System.cmd("ffmpeg", ["-y", "-sseof", "-0.25", "-i", in_path, "-frames:v", "1", "-q:v", "3", out_path], stderr_to_stdout: true)`, on exit 0 call `Whn.Fal.upload(out_path)`, clean up both tmp files in an `after` block. Test: generate a 2s fixture mp4 in setup via `System.cmd("ffmpeg", ["-y", "-f", "lavfi", "-i", "testsrc=duration=2:size=144x256:rate=10", fixture_path])`, serve it or pass a `file://`-style branch — simplest: let `last_frame/1` also accept a local path (skip download when the string is an existing file) — and stub the upload by setting `Application.put_env(:whn, :fal_impl, StubImpl)` in the test (an inline `defmodule` implementing `Whn.Fal` callbacks; `upload/1` asserts the jpg exists and returns `{:ok, "stub://frame.jpg"}`). Restore env in `on_exit`.
- **Done when:** `(cd server && mix test test/whn/frames_test.exs)` exits 0 (FAL-02); `grep sseof server/lib/whn/frames.ex` matches.
- **Covers:** D-06, RESEARCH ffmpeg recipe

### III. Timed fal spike — measure the latency the timing model assumes

- **Files:** `server/scripts/fal_spike.exs`, `.jira/sprints/2026-08-31-live-episode-mvp/fal-spike.log`
- **Read first:** RESEARCH.md "Risks & unknowns" (what the spike must validate), `research-external.md` H3 Max / FLUX / vision schemas, CONTEXT.md D-05/D-06
- **Action:** Script run via `mix run scripts/fal_spike.exs` (requires FAL_KEY; abort with a clear message if unset). Wrap each stage in `:timer.tc` and `IO.puts` a `STAGE <name> <ms>ms` line: (1) `flux` opening frame, prompt ~"Lagos street, young Nigerian man checking phone, golden hour", `image_size: %{width: 720, height: 1280}`; (2) `i2v` 10s: `duration: 10, resolution: "480P", prompt_expansion_mode: "disabled", seed: 42`, `image_url` = the flux HOSTED url (validates hosted-URL acceptance — no data URI); (3) `Whn.Frames.last_frame/1` on the i2v output (full download+extract+upload round-trip); (4) `t2v` 10s: `duration: 10, resolution: "480P", aspect_ratio: "9:16", prompt_expansion_mode: "balanced", seed: 42`; (5) `vision` with `model: "google/gemini-2.5-flash-lite"`, the frame from (3) in `image_urls`, and a prompt requesting a one-sentence JSON reply (validates D-05 image-attached calls). Print a `TOTAL <ms>` line and a `BUDGET CHECK` line comparing i2v ms against the 20_000ms remaining-scene+bridge budget. Run it once and save full output: `(cd server && mix run scripts/fal_spike.exs) 2>&1 | tee ../.jira/sprints/2026-08-31-live-episode-mvp/fal-spike.log`. Cost ≈ $0.50–$1.10 (two 10s 480P clips + flux + vision) — run once, don't loop.
- **Done when:** `grep -c '^STAGE' .jira/sprints/2026-08-31-live-episode-mvp/fal-spike.log` = 5 and a `TOTAL` line exists (FAL-03).
- **Covers:** D-05, D-06, D-16, RESEARCH latency/FLUX/vision unknowns

## Nyquist criteria for this plan

- [ ] `mix compile --warnings-as-errors` exits 0 with the 5-callback wrapper (FAL-01)
- [ ] Frames test green using the local ffmpeg recipe (FAL-02)
- [ ] fal-spike.log holds 5 per-stage wall-clock lines + total (FAL-03)

## Risks accepted in this plan

- fal_ex is 14 months dormant; if `FalEx.subscribe/2` misbehaves the swap is confined to `fal_ex_impl.ex` (Req over the 4 documented queue URLs) — documented fallback, not built.
- Spike numbers are a single sample, not a distribution; the hold state (D-07) is the systemic mitigation if real latency exceeds budget.
- H3 Max promo pricing ends 2026-09-01; the spike's absolute cost may double after today. Behavior is unaffected.
- `last_frame/1` accepting local paths slightly widens the interface — accepted for testability.
