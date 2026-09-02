# Research: external — 2026-09-02-frame-chained-continuity

Verification pass only; the sprint is in-repo. Four claims checked, all with fetched or empirical sources.

## Summary

- **MiniMax h3-max i2v confirmed:** `image_url` takes a hosted URL as the first frame and the output aspect ratio follows it; `end_image_url` exists ("first-to-last keyframe generation") — a future option for bridges that end on the next scene's opening frame. Not in scope this sprint.
- **`-sseof -0.25` verified empirically** (ffmpeg 9.0.1, the repo's nix devshell binary, and a real h3-max clip from the 2026-08-31 spike): it selects the frame at container-duration − 0.25s. On the real clip (10.144s) it grabbed pts 9.917 — 0.167s before the true final frame, satisfying "the last second."
- **One real failure mode:** h3-max output carries an AAC audio track; `-sseof` measures from *container* duration. If audio outlasts video by >~0.2s, the seek target lands past the last video frame and ffmpeg exits non-zero ("Nothing was written into output file") — the repo's error branch catches it. A retry with a larger negative offset (e.g. `-sseof -1`) recovers only if video ends within that window of container end. On the observed real clip the overhang was 0.06s — safe.
- **fal storage longevity is a non-issue for 40–60s:** the frame uploaded via the FalEx presigned flow on 2026-08-31 is still served today (HTTP 200, `cache-control: public, max-age=5184000, immutable` = 60-day cache, `x-fal-storage-type: tigris`). Docs say retention is configurable via `X-Fal-Object-Lifecycle-Preference`; no minutes-scale default anywhere.
- **`fal-ai/ffmpeg-api/extract-frame` still exists** with `frame_type: "first" | "middle" | "last"` (default `"first"`), output `{images: [{url, ...}]}` — the previous sprint's hosted-fallback note remains valid.

## Findings

### MiniMax h3-max image-to-video (item 1)

Fetched https://fal.ai/models/minimax/h3-max/image-to-video/api (2026-09-02):

- `image_url` — "Optional URL of the image to use as the first frame. When provided, the output aspect ratio follows this image." Hosted URLs accepted; the repo already feeds it fal.media URLs (spike log confirms a successful i2v run from an uploaded frame).
- `end_image_url` — "Optional URL of the image to use as the last frame, for first-to-last keyframe generation." Exists today. Future option: generate the bridge with `image_url` = scene-end frame AND `end_image_url` = next scene's opening frame, removing the bridge-last-frame extraction step entirely. Out of scope per brief; recorded for accuracy.
- No other frame-control params in the schema.
- Matches the previous sprint's findings verbatim (`.jira/sprints/2026-08-31-live-episode-mvp/research-external.md:33`) — no drift since 2026-08-31.

### ffmpeg `-sseof -0.25` fidelity (item 2)

Official docs (https://ffmpeg.org/ffmpeg.html): "-sseof position (input) — Like the `-ss` option but relative to the 'end of file'. That is negative values are earlier in the file, 0 is at EOF." Input seeking jumps to the nearest preceding keyframe, then (with default `-accurate_seek`) decodes and discards up to the exact target — so keyframe placement does not degrade accuracy when transcoding to jpg, only speed.

Empirical, ffmpeg 9.0.1 (the repo devshell's binary), exact repo command `-y -sseof -0.25 -i <clip> -frames:v 1 -q:v 3` (`server/lib/whn/frames.ex:46`):

| Clip | Result |
|---|---|
| Synthetic 6s/24fps, single keyframe at t=0 (worst case) | exit 0; frame at pts 5.75 = duration − 0.25 exactly |
| Real h3-max i2v clip from spike (10.144s, h264+aac, 24fps) | exit 0; frame at pts 9.917 (last video frame is 10.083) |
| 0.2s clip (shorter than the offset) | exit 0; seek clamps to start, frame produced |
| Video 5s + audio 6s (container duration 6.0) | **exit 234**, no output; "Nothing was written into output file, because at least one of its streams received no packets." |

The extracted frame from the real clip byte-matched the frame the spike uploaded (37,297 bytes both) — the pipeline's extraction is deterministic and already proven against real h3-max output.

Failure-mode detail: `-sseof` is computed from container duration (mp4 `format.duration` covers the longest stream). h3-max clips DO contain an AAC track (ffprobe on the real clip: `codec_type=video h264` + `codec_type=audio aac`), so an audio overhang > (0.25 − one frame interval ≈ 0.21s at 24fps) would push the seek target past the last video frame → zero frames → non-zero exit, which `Whn.Frames.extract/2` surfaces as `{:error, {:ffmpeg, exit_code, output}}`. Observed overhang on the real clip: 0.061s (duration 10.144 vs last video pts 10.083). Retry behavior tested: `-sseof -1` still failed on the synthetic 1s-overhang clip (target 5.0 > last video pts 4.958); `-sseof -1.05` succeeded. So a `-sseof -1` fallback covers audio overhangs up to ~0.96s and still lands within "the last second" of video; it is not a universal cure. `-map 0:v` does not change the seek arithmetic (tested; still exit 234).

User-intent check: both `-0.25` and `-1` yield a frame within the final second of the clip (24fps ⇒ duration − last-frame-pts ≈ 0.042s for the video stream itself). `-0.25` satisfies "the last second in that frame."

### fal storage upload longevity (item 3)

- Live check (2026-09-02): the frame uploaded 2026-08-31 via the rest.alpha.fal.ai presigned flow — `https://v3b.fal.media/files/b/0aa89521/gpwq_pzOXCsO1a6VFiLSg_whn_frame_4485.jpg` — returns HTTP 200 with `cache-control: public, max-age=5184000, immutable` (60 days) and `x-fal-storage-type: tigris`. The generated i2v clip URL from the same day is also live. Empirical floor: ≥2 days.
- Docs (https://fal.ai/docs/documentation/model-apis/media-expiration, fetched): retention is configurable via the `X-Fal-Object-Lifecycle-Preference` header (`expiration_duration_seconds: <n>` or `null` for no expiration); "Files you upload as inputs via fal_client.upload_file are also stored on the CDN. Both input uploads and output media are subject to the same retention controls." No numeric default is stated on the page; https://fal.ai/docs/documentation/model-apis/fal-cdn likewise says only "CDN file retention is configurable."
- Conclusion for the plan: nothing documented or observed expires in minutes; a scene-end frame surviving 40–60s between cycles is far inside the empirical 2-day floor.

### Hosted extract-frame fallback (item 4)

Fetched https://fal.ai/models/fal-ai/ffmpeg-api/extract-frame/api (2026-09-02): endpoint exists. Input: `video_url` (required), `frame_type` enum `first | middle | last`, default `"first"`. Output: `{images: [{url, content_type?, file_name?, file_size?, width?, height?}]}`. The previous sprint's fallback note stays valid; note the default is `"first"`, so `frame_type: "last"` must be explicit.

## Open questions

- No documented numeric default for fal CDN file retention (docs say "configurable" only). Empirically ≥2 days with a 60-day cache header — sufficient for this sprint; if frames ever need to persist across days, set `X-Fal-Object-Lifecycle-Preference` explicitly.
- Audio-overhang size on h3-max outputs is only sampled once (0.06s on one real clip). Whether MiniMax ever emits audio >0.2s longer than video is unknown; the ffmpeg non-zero exit makes the failure loud, and a wider-offset retry is a cheap guard if the planner wants one.

## Sources

### Primary (HIGH confidence)
- https://fal.ai/models/minimax/h3-max/image-to-video/api — fetched 2026-09-02; `image_url` / `end_image_url` descriptions verbatim.
- https://fal.ai/models/fal-ai/ffmpeg-api/extract-frame/api — fetched 2026-09-02; `frame_type` enum and output schema.
- https://ffmpeg.org/ffmpeg.html — fetched; `-sseof` definition and `-accurate_seek` input-seek semantics verbatim.
- https://fal.ai/docs/documentation/model-apis/media-expiration — fetched; lifecycle header, input-uploads-same-retention quote.
- https://fal.ai/docs/documentation/model-apis/fal-cdn — fetched; "CDN file retention is configurable."
- Empirical: ffmpeg 9.0.1 (repo nix devshell binary) runs of the exact `server/lib/whn/frames.ex:46` command on synthetic clips and the real h3-max clip; curl HEAD/GET of live fal.media URLs from `.jira/sprints/2026-08-31-live-episode-mvp/fal-spike.log:6,8` (2026-09-02).
- In-repo: `server/lib/whn/frames.ex:33-52` (fetch/extract/error propagation); `.jira/sprints/2026-08-31-live-episode-mvp/research-external.md:31-33` (prior i2v schema findings, now re-verified).

### Secondary (MEDIUM confidence)
- WebSearch summary of fal retention docs stating request inputs/outputs (JSON payloads) are kept 30 days by default — consistent with the fetched media-expiration page but the 30-day figure was not verbatim on the page I fetched; applies to request payloads, not CDN files.

### Tertiary (LOW confidence)
- General claim that mp4 container duration ≈ last video pts + one frame interval for video-only files — inferred from the two probed clips, not from a spec citation. Only load-bearing for the audio-overhang margin arithmetic.
