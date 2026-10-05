# fal and media

## fal_ex 0.1.0 queue polling never worked

The library polls `/status/<id>` and `/result/<id>`, which fal's current API answers with 405. Synchronous submits returned before any polling happened, so the bug stayed hidden.

The paths that work are `queue.fal.run/<owner>/<alias>/requests/<id>/status`, `/requests/<id>`, and `/requests/<id>/cancel`. Request URLs use only the owner and alias, so `minimax/h3-max/image-to-video` becomes `minimax/h3-max`. This project vendors a patched copy.

## fal_ex storage upload points at a dead host

The storage client builds its upload host by string replacement into `v3.fal-cdn.com`, which no longer resolves. Use fal's current storage REST flow instead: an authenticated initiate call, then a PUT of the bytes to the presigned URL it returns.

## Default HTTP timeouts kill generation calls

Hackney's default receive timeout is five seconds, and video generation takes far longer. Raise the timeout to match the request-layer budget.

## Calibrate stage budgets on the real path

The video budget was measured against synchronous calls. On the queue endpoint the same call ranged from a few seconds to well past the old budget, and healthy segments died as timeouts. Budgets now live in app config so a deployment can tune them without a release.

## Network-level fal failures

`fal.run` once reset TLS from one network while `queue.fal.run` kept working. Check both hosts before debugging the client. A host-file pin to the queue IP only helps fast synchronous calls, because that host ignores async mode and long jobs hang.

## ffmpeg `-sseof` misses the last frame when audio is longer

`-sseof` seeks from container duration. When the audio track runs past the video, a seek of -0.25 seconds lands after the final video frame and ffmpeg exits with "Nothing was written into output file".

Fix: on failure, retry once from -1 second. Keep a test fixture with a short video track and a longer audio track.

## Best-effort steps must not fail the main flow

Extracting the scene's last frame runs after every segment is delivered. If it fails, log and skip. Raising there would push a playable episode into a hold state.

## Whitespace cleanup can merge prompt lines

Removing dialogue left doubled spaces, and a squeeze regex collapsed whitespace across newlines. A speaker label merged into the escalation line below it, and the video model read the ladder text aloud.

Fix: handle prompt text line by line. Drop labeled dialogue lines whole and never collapse whitespace across a newline. Add a test that every emitted prompt has exactly one instance of each labeled line.

## Retries need a fixed seed

One retry per generation stage with identical arguments and a fixed seed keeps the retry idempotent. A recording mock that can fail once on demand tests the retry path without spending credits.
