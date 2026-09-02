---
sprint: 2026-09-02-frame-chained-continuity
plan: II
wave: II
goal: Scene-end frames chain each cycle into the next (pipeline emits {:last_frame, url}; server stores it latest-wins and seeds the next bridge ctx), vote_closed waits a scheduled 2.5s reveal after vote_locked, and the stale EP-08 predicate is superseded — proven by the server suite passing with all nine FC-/REV- predicates sensed and zero web/ changes.
worktree: false
branch: jira/2026-08-31-live-episode-mvp
issue: none
depends_on: [I]
parallel_with: []
files_modified:
  - server/lib/whn/pipeline.ex
  - server/lib/whn/frames.ex
  - server/test/support/fal_mock.ex
  - server/test/whn/pipeline_test.exs
  - server/test/whn/frames_test.exs
covers:
  - D-01
  - D-03
  - D-04
  - "GOAL: scene-end frame extracted after the final segment, off the delivery path, feeding the next bridge"
  - "RESEARCH: extraction hooked in run_segments' shared path after the final segment's notify (opening chains for free)"
  - "RESEARCH: trailing extraction best-effort — log + skip, never {:error, :frame, ...}"
  - "RESEARCH: keep -sseof -0.25 primary; retry once with -sseof -1 on non-zero ffmpeg exit (audio overhang)"
effects:
  - FC-01
  - FC-04
  - FC-06
---

# Plan II: Pipeline — trailing scene-end extraction, overhang-safe frames

**Sprint goal:** see frontmatter `goal:`.
**This plan delivers:** the producer side of frame chaining — the pipeline extracts the final segment's last frame after delivering it and notifies `{:pipeline, beat, {:last_frame, url}}` (D-01), best-effort (D-03), with the ffmpeg audio-overhang retry in `Whn.Frames` (D-04). Depends on Plan I: without the server's exempt head, a matching-beat `{:last_frame, url}` crashes the EpisodeServer in the integration suite.

**Environment:** run inside `nix develop` from the repo root; Postgres on 57432 must be up; tests via `mix test` from `/home/drew/kit/whn/server`. `Whn.PipelineStub` stays untouched — it produces no messages by design.

## Tasks

### I. Trailing extraction and `{:last_frame, url}` emission

- **Files:** `server/lib/whn/pipeline.ex`
- **Read first:** `server/lib/whn/pipeline.ex` (whole file — `run_cycle`, `run_opening`, `run_segments`, `next_frame`, `report`, `notify`), `.jira/sprints/2026-09-02-frame-chained-continuity/research-codebase.md` §1 (pipeline side), CONTEXT.md D-01/D-03
- **Action:** Per D-01/D-03:
  1. Change `defp next_frame(2, _url), do: {:ok, nil}` (currently line 127) to `defp next_frame(2, url), do: {:ok, url}` and update its comment: the final segment's own extraction is skipped inside the loop, but its url flows out so the cycle can chain its end frame. `run_segments` then returns `{:ok, final_segment_url}` on success — segment delivery order is untouched because `notify(..., {:segment_ready, 2, url})` still precedes this.
  2. Add `require Logger` to the module (it currently has none).
  3. In BOTH `run_cycle/2` and `run_opening/2`, between computing `outcome` and `report(outcome, dest, ctx.beat)`, insert `chain_frame(outcome, dest, ctx.beat)` and add:

     ```elixir
     # Scene-end chaining is best-effort: the scene is already delivered when
     # this runs, so a failure logs and skips — it must never surface as
     # {:error, :frame, _} and flip a playable episode to hold. Single attempt,
     # no retry: the next bridge falls back to t2v exactly as before.
     defp chain_frame({:ok, last_url}, dest, beat) when is_binary(last_url) do
       case Whn.Frames.last_frame(last_url) do
         {:ok, frame_url} ->
           notify(dest, beat, {:last_frame, frame_url})

         {:error, reason} ->
           Logger.warning("scene-end frame extraction failed for beat #{beat}: #{inspect(reason)}")
       end
     end

     defp chain_frame(_error_or_nil, _dest, _beat), do: :ok
     ```

     Note it deliberately calls `Whn.Frames.last_frame/1` directly, NOT `extract_frame/1` (no `with_retry` — D-03 and Claude's-discretion in CONTEXT.md: single attempt keeps the tail short and the failure path deterministic under `fail_on_call`). Do not touch `with_retry`, `report`, or the intra-segment `extract_frame` path. Update the moduledoc's cycle description to mention the trailing scene-end extraction.
- **Done when:** `grep -n "chain_frame\|{:last_frame" server/lib/whn/pipeline.ex` shows the helper, both call sites (`run_cycle`, `run_opening`), and the notify; `grep -n "next_frame(2" server/lib/whn/pipeline.ex` shows `{:ok, url}` not `{:ok, nil}`; `mix compile --warnings-as-errors` exits 0.
- **Covers:** D-01, D-03, FC-01 (implementation)

### II. Audio-overhang retry in `Whn.Frames`

- **Files:** `server/lib/whn/frames.ex`, `server/test/whn/frames_test.exs`
- **Read first:** `server/lib/whn/frames.ex` (whole file), `server/test/whn/frames_test.exs` (StubFal + fixture pattern), CONTEXT.md D-04, RESEARCH.md pitfall "Audio outlasts video on real H3 Max clips"
- **Action:** Per D-04, refactor `extract/2` so the ffmpeg invocation takes the `-sseof` offset as a parameter; try `"-0.25"` first (byte-identical args otherwise), and on `{:error, {:ffmpeg, _, _}}` retry once with `"-1"`, returning the second attempt's result as-is. Comment the why: the AAC track can outlast the video stream, and `-sseof` measures from container duration, so an overhang > ~0.25s seeks past the last video frame ("Nothing was written into output file"). Add a test (comment it `# FC-06`) building an overhang fixture — video 1s, audio 1.5s, 0.5s overhang, chosen so `-0.25` fails (seek at 1.25s, past the 1s video) and `-1` succeeds (seek at 0.5s):

  ```elixir
  {_output, 0} =
    System.cmd(
      "ffmpeg",
      ["-y", "-f", "lavfi", "-i", "testsrc=duration=1:size=144x256:rate=10",
       "-f", "lavfi", "-i", "sine=frequency=440:duration=1.5", fixture],
      stderr_to_stdout: true
    )
  ```

  then `assert {:ok, "stub://frame.jpg"} = Whn.Frames.last_frame(fixture)`. The existing "not a readable video" test must still pass (both attempts fail → error propagates).
- **Done when:** `grep -n '"-1"' server/lib/whn/frames.ex` shows the retry offset; `mix test test/whn/frames_test.exs` exits 0 including the new overhang test.
- **Covers:** D-04, FC-06

### III. `FalMock.fail_on_call/2` and the pipeline predicates

- **Files:** `server/test/support/fal_mock.ex`, `server/test/whn/pipeline_test.exs`
- **Read first:** `server/test/support/fal_mock.ex` (whole file), `server/test/whn/pipeline_test.exs` (setup, `ctx/1`, CEL-04/05/06 shapes), CONTEXT.md Claude's-discretion note on `fail_on_call`
- **Action:**
  1. Add to `Whn.FalMock` an additive `fail_on_call(fun, n)` — arms a single `{:error, :fal_flaked}` for the Nth call (1-based, counted per `fun`) — by tracking per-fun call counts in the Agent state and checking `fail_on: %{fun => n}` inside `dispatch/3`. `fail_once/1` and all existing behavior stay untouched. Document it in the moduledoc line style already there.
  2. Add a test `# FC-01`: `start_cycle(self(), ctx(%{last_frame_url: "mock://prev.jpg"}))`; consume celeris, bridge_ready, and the three `segment_ready` messages in order (same shape as CEL-04); then `assert_receive {:pipeline, 1, {:last_frame, frame_url}}, 10_000` with `assert frame_url =~ "mock://frame-"`; end with `refute_receive {:pipeline, _, {:error, _, _}}, 100`.
  3. Add a test `# FC-04`: `Whn.FalMock.fail_on_call(:upload, 4)` then `start_cycle(self(), ctx(%{last_frame_url: "mock://prev.jpg"}))`. Upload-call arithmetic (document it in a comment): bridge-frame extraction (1), segment-0 extraction (2), segment-1 extraction (3), trailing extraction (4) — no failures armed on 1-3, and the trailing attempt is single-shot, so call 4 deterministically hits it. Assert all three `segment_ready` arrive, then `refute_receive {:pipeline, _, {:error, _, _}}, 100` and `refute_receive {:pipeline, _, {:last_frame, _}}, 100`.
  4. Do NOT rewrite CEL-04/05/06 or the opening test — the new message is additive and none of them assert an exhaustive message set (verified in research-codebase.md).
- **Done when:** `mix test test/whn/pipeline_test.exs` exits 0 with the two new tests; `grep -n "fail_on_call" server/test/support/fal_mock.ex server/test/whn/pipeline_test.exs` shows the definition and both the arming call; CEL-04/05/06 pass unmodified.
- **Covers:** FC-01, FC-04, D-03 (failure-path evidence)

## Nyquist criteria for this plan

- [ ] `mix test test/whn/pipeline_test.exs` exits 0 — FC-01 (order: `{:segment_ready, 2, _}` before `{:last_frame, _}`, no error) and FC-04 (all segments delivered, no error, no frame message) sensed
- [ ] `mix test test/whn/frames_test.exs` exits 0 — FC-06 sensed by the overhang fixture test
- [ ] `mix test` (full suite) exits 0 — integration tests now flow the real `{:last_frame, url}` into the wave-I server head; `drain_tasks` absorbs the extra ~3s extraction tail
- [ ] `mix compile --warnings-as-errors` exits 0 in `server/`
- [ ] `git diff --stat` shows no change to `server/test/support/pipeline_stub.ex` and nothing under `web/`

## Risks accepted in this plan

- The `-sseof -1` retry ceiling (~0.96s of usable headroom) rests on one real overhang sample (0.06s) plus synthetic reproduction — accepted; observe in production logs (future).
- A genuine upload flake on the trailing extraction loses one cycle's chaining (single attempt, D-03) — the next bridge degrades to t2v, the designed fallback; accepted.
- The trailing extraction adds ~3s to the cycle task's lifetime after the last segment is delivered — off the playback path by construction (notify precedes extraction), and 3–6s inside the lock margin under spike timings; a retry-delayed segment pushing the frame past lock just means that cycle's bridge falls back / the frame seeds a later beat (latest-wins) — accepted.
- FINAL FRAME HYGIENE (readable end shots) in `server/lib/whn/prompts.ex` becomes load-bearing for production continuity for the first time — no code change needed, flagged for prompt-quality review in a future sprint.
- Live-fal behavior of the full chain is mock-verified only this sprint (hermetic constraint from the brief); a production smoke happens outside the suite.
