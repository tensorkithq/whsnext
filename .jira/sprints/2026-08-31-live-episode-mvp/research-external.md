# Research: external — 2026-08-31-live-episode-mvp

## Summary

- fal queue over plain HTTP is fully documented: `POST https://queue.fal.run/{model_id}` with `Authorization: Key $FAL_KEY`, poll `GET .../requests/{id}/status`, fetch `GET .../requests/{id}`. Webhooks exist as an alternative (`?fal_webhook=URL` on submit).
- MiniMax H3 Max t2v **does support 9:16** (enum: 21:9, 16:9, 4:3, 1:1, 3:4, 9:16). Resolution enum is **480P/768P only — no 1080P**. Duration is integer 5–15 (default 5), so 10s segments are valid. i2v has no aspect_ratio param; output aspect follows the input image. No fallback plan needed, and the FLUX-frame → i2v chain controls aspect via the frame anyway.
- Pricing: promo (50% off) 480P $0.025/s, 768P $0.04/s ends **September 1, 2026** — i.e. tomorrow. Post-promo: 480P $0.05/s, 768P $0.08/s → a 10s 480P clip costs $0.50; a 30s scene (3 segments) $1.50. Generation latency for a 10s/480P clip is **not documented** anywhere official.
- `fal_ex` hex package (0.1.0) matches the needed surface (run/subscribe/queue submit-status-result-cancel, FAL_KEY config, storage upload, webhook_url) but is dormant: published Jun 22 2025, 6 commits, 0 stars, 247 total downloads, no pushes since Jun 2025.
- iOS Safari allows muted+playsinline autoplay, but **ignores `preload="auto"`** (only metadata preloads; `#t=0.001` fragment is the common workaround) — this directly affects the dual-`<video>` preload strategy.

## Findings

### fal queue API over HTTP (no JS client)

Verified at the official queue doc (HIGH):

- Submit: `POST https://queue.fal.run/{model_id}`, headers `Authorization: Key $FAL_KEY`, `Content-Type: application/json`, body = model input JSON.
- Submit response: `request_id`, `status_url`, `response_url`, `cancel_url`, `queue_position`.
- Status: `GET https://queue.fal.run/{model_id}/requests/{request_id}/status` (append `?logs=1` for logs). `status` ∈ `IN_QUEUE` (with `queue_position`), `IN_PROGRESS` (with `logs`), `COMPLETED` (with `metrics`).
- Result: `GET https://queue.fal.run/{model_id}/requests/{request_id}` → model output JSON.
- Cancel: `PUT .../requests/{request_id}/cancel` → `CANCELLATION_REQUESTED` / `ALREADY_COMPLETED` / `NOT_FOUND`.
- Webhook alternative: append `?fal_webhook=https://your-server/hook` to the submit POST; fal POSTs `{request_id, status: "OK"|"ERROR", payload}` on completion. Signature verification via `X-Fal-Webhook-Signature` header (MEDIUM — search snippet, not fetched).
- Recommended poll interval: not stated in the docs I read.

### minimax/h3-max/text-to-video (HIGH — /api page + OpenAPI JSON)

- Input: `prompt` (string, required), `prompt_expansion_mode` (required; enum `balanced`|`quality`; "balanced" ~1s, "quality" up to ~30s extra), `duration` (integer, min 5, max 15, default 5), `resolution` (enum `480P`|`768P`, default `768P`), `aspect_ratio` (enum `21:9`,`16:9`,`4:3`,`1:1`,`3:4`,`9:16`, default `16:9`), `seed`, `enable_safety_checker` (default true), `sync_mode` (base64 instead of CDN URL).
- Output: `video` (File: `url`, `content_type`, `file_name`, `file_size`), `expanded_prompt`, `timings` (per-stage seconds).
- 16:9/768P renders at 1344x768 @ 24fps (MEDIUM — search snippet); 9:16 pixel dims not documented on the pages fetched.

### minimax/h3-max/image-to-video (HIGH — /api page)

- Same fields as t2v **minus** `aspect_ratio`, **plus** `image_url` ("Optional URL of the image to use as the first frame. When provided, the output aspect ratio follows this image") and `end_image_url` (first-to-last keyframe generation).
- With no image, defaults to 16:9. So vertical output for i2v = supply a 9:16 opening frame.
- Output schema identical to t2v (`video.url` etc.).

### H3 Max pricing and latency (HIGH — model landing page)

- Per-second pricing, promotional 50% off through Aug 31 2026: 480P $0.025/s, 768P $0.04/s. From Sept 1 2026: 480P $0.05/s, 768P $0.08/s.
- Cost math at post-promo 480P: 10s segment $0.50; 30s scene $1.50; scene + 10s bridge ≈ $2.00 per decision cycle.
- No documented wall-clock generation time for a 10s clip; only prompt-expansion latency is documented. The brief's timing model (bridge generates in 10–12s of playback headroom) rests on an unverified latency assumption.

### openrouter/router and openrouter/router/vision (HIGH — /api pages)

- `openrouter/router` input: `model` (required; `provider/model-name` ids, e.g. `google/gemini-2.5-flash`), `prompt` (required), `system_prompt`, `temperature` (default 1), `max_tokens`, `reasoning` (bool), `enable_web_search`, `web_search_options`. Output: `{output (required), reasoning?, partial?, error?, usage: {prompt_tokens, completion_tokens, total_tokens, cost}}`. Billed on actual token usage; example showed `cost: 0.0005795` for 267 tokens.
- `openrouter/router/vision` input: `prompt` (required), `model` (required), `image_urls` (optional list of strings; hosted URLs and base64 data URIs — data-URI acceptance is MEDIUM, from the page summary), `pdf_urls`, `system_prompt`, `temperature`, `max_tokens`. Output: `{output, usage}`.
- `image_urls` being optional makes a text-only call on the vision route schema-valid; whether it actually succeeds is not documented.
- Reference model `google/gemini-2.5-flash-lite` exists on OpenRouter: vision input supported, 1,048,576-token context, 65,535 max completion, $0.10/M input, $0.40/M output (HIGH — OpenRouter model page).

### fal-ai/flux-2-pro (HIGH — /api page)

- Input: `prompt` (required), `image_size` (enum `square_hd, square, portrait_4_3, portrait_16_9, landscape_4_3, landscape_16_9`, default `landscape_4_3`; "For custom image sizes, you can pass the `width` and `height` as an object" — so `{width: 720, height: 1280}` is the documented path to 720x1280; no max/step constraints documented), `seed`, `safety_tolerance` (1–5, default 2), `enable_safety_checker` (default true), `output_format` (`jpeg`|`png`, default `jpeg`), `sync_mode`.
- Output: `{images: [{url, content_type, file_name, file_size, width, height}], seed}`. No `num_images` param on this endpoint.

### fal-ai/ffmpeg-api/extract-frame — hosted alternative to local ffmpeg (HIGH — /api page)

- Input: `video_url` (required), `frame_type` (enum `first`|`middle`|`last`, default `first`). No custom timestamps.
- Output: `{images: [{url, content_type?, file_name?, file_size?, width?, height?}]}`.
- `frame_type: "last"` covers the pipeline's last-frame-extract step without downloading the video server-side. Pricing $0.0002/s of video (MEDIUM — search snippet). Tradeoff vs local ffmpeg: one extra queue round-trip + network latency per segment; local ffmpeg (already in the nix flake) has zero queue latency but requires downloading the mp4.

### fal_ex hex package (scope addition)

- hexdocs (HIGH): version 0.1.0; config via `FAL_KEY` env, `FAL_KEY_ID`+`FAL_KEY_SECRET`, app config `:fal_ex, api_key:`, or `FalEx.config(credentials: ...)`. API: `FalEx.run/2` (sync), `FalEx.subscribe/2` (queue + progress), `FalEx.Queue.submit/3` (accepts `webhook_url`), `FalEx.Queue.status/3` (`logs: true`), `FalEx.Queue.result/3`, `FalEx.Queue.cancel/3`, `FalEx.Storage.upload/2`, plus `FalEx.stream/2` and `FalEx.realtime/0` (WebSockex). Tesla-based. MIT. Arbitrary model-id strings — matches coordinator's verification.
- Maturity (HIGH — hex.pm + GitHub API): published Jun 22 2025, 247 all-time downloads, repo dantame/fal_ex has 6 commits, 0 stars, 0 open issues, last push 2025-06-22 — 14 months dormant. Tradeoff: working surface today vs. no maintenance signal; fallback named by coordinator is a thin Req wrapper over the 5 queue endpoints above (small: the whole HTTP surface is 4 URLs + 1 header).

### phoenix npm client + types

- npm registry (HIGH): `phoenix` latest is **1.8.13** (published 2026-08-25); the 1.7.x line ends at 1.7.24. Package ships ESM (`./priv/static/phoenix.mjs`) + CJS via `exports` map — no special Vite handling needed. No bundled TypeScript types.
- `@types/phoenix` latest is **1.6.7** (2025-12-08) — lags the 1.8 client; core Socket/Channel/Presence types are stable but new options may be untyped.
- Client API (HIGH — phoenix.hexdocs.pm/js, v1.8.13): `new Presence(channel, opts)`, `presence.onSync(cb)`, `presence.list(chooser)`, `onJoin((id, current, newPres))`, `onLeave((id, current, leftPres))`; Socket opts include `params`, `authToken`, `heartbeatIntervalMs`, `reconnectAfterMs`, `rejoinAfterMs`.
- Version note: the sprint scaffold pins phoenix 1.7.x on the web side (per task brief) while the server is Phoenix 1.8 — npm 1.8.13 exists and matches the server; wire protocol (V2 serializer) is compatible either way, but aligning versions is available.

### TanStack Router — code-based routing

- Docs (HIGH): code-based routing without `@tanstack/router-plugin` is supported — `createRootRoute()` / `createRootRouteWithContext<T>()`, `createRoute({getParentRoute, path, component})`, manual tree via `routeTree = rootRoute.addChildren([...])`, then `createRouter`. Docs state "Code-based routing is not recommended for most applications" but it is first-class and uses the same route-tree model.
- npm registry (HIGH): `@tanstack/react-router` latest **1.170.32** (2026-08-22) — still the ^1.x line. `peerDependencies: react ">=18.0.0 || >=19.0.0"` → React 19 supported. `engines.node >= 20.19`.

### Phoenix 1.8 server conventions

- Phoenix.Presence (HIGH — hexdocs v1.8.13): `use Phoenix.Presence, otp_app: :my_app, pubsub_server: MyApp.PubSub`; supervise after PubSub, before Endpoint; in channel: `send(self(), :after_join)` from `join/3`, then `Presence.track(socket, key, meta)` + `push(socket, "presence_state", Presence.list(socket))` in `handle_info(:after_join, ...)`; optional `fetch/2` override to enrich metas.
- `check_origin` (HIGH — Phoenix.Endpoint hexdocs v1.8.13): default `true` validates the Origin header against the endpoint `:url` `:host`; accepts `false` (dev only — CSWSH risk), an explicit origin list with wildcards (scheme/host/port), `:conn`, or an MFA `{Mod, fun, args}` receiving the request `%URI{}` and returning boolean. For the Vite-dev setup, two documented options: (a) Vite `server.proxy` with `ws: true` to `localhost:4000` (same-origin from the browser's view), or (b) direct browser→4000 socket with `check_origin: ["http://localhost:5173"]` in `dev.exs`. Channel WebSockets don't use CORS — origin checking is the only cross-origin gate.
- Ecto/postgrex non-default port (HIGH — ecto_sql v3.14.0 hexdocs): Repo config accepts `:port` (default 5432) alongside `:hostname/:username/:password/:database` — `port: 57432` is all that's needed.

### Mobile autoplay + dual-player caveats

- iOS Safari (HIGH — WebKit blog "New video policies for iOS"): `<video autoplay>` plays without gesture iff the media has no audio track **or** `muted` is set; must be visible in viewport/DOM; if the element gains audio or is unmuted without a gesture, playback pauses; `video.play()` returns a Promise that rejects when conditions aren't met; `playsinline` required to avoid fullscreen takeover on iPhone.
- Chrome (HIGH — developer.chrome.com/blog/autoplay): "Muted autoplay is always allowed" (desktop and Android); unmuted requires prior interaction with the domain (tap/click) or, desktop-only, MEI threshold; on mobile, unmuted autoplay also allowed for home-screen/PWA installs; `play()` rejects with `NotAllowedError` when blocked. Applies from Chrome 66+.
- Preload caveat (MEDIUM — multiple agreeing community sources incl. mux/videojs issues; no current official Apple doc fetched): iOS Safari ignores `preload="auto"` and effectively only honors metadata preload; video bytes aren't fetched until playback starts. Common workarounds: append `#t=0.001` to the URL to force first-frame fetch, or call `muted play()` then `pause()` to warm the buffer. Impact: the dual-`<video>` "preload the next segment" strategy needs one of these on iOS or the swap will show a fetch stall.
- Unmuted playback for the story experience requires one real user gesture first (both platforms) — a tap-to-start gate satisfies iOS and Chrome Android simultaneously.

## Open questions

- Real-world H3 Max generation wall-clock at 480P/10s is undocumented; the brief's 10–12s bridge window needs an empirical spike before the timing model is trusted.
- Whether a text-only call on `openrouter/router/vision` actually succeeds (schema allows it; behavior unverified). Reference impl behavior is a codebase-focus question.
- FLUX 2 Pro custom `{width, height}` limits (max dims, multiple-of-N constraints) are not documented; 720x1280 needs a smoke test.
- Data-URI acceptance on `image_urls` came from a page summary, not a verbatim schema quote — verify once during the pipeline spike (or upload frames via `FalEx.Storage.upload` and sidestep it).
- fal queue: no documented recommended poll interval or rate limit for status polling.
- H3 Max pricing page was the t2v landing page; i2v assumed same per-second rate (not separately verified).
- `@types/phoenix` (1.6.7) vs phoenix 1.8.13 client: gap unaudited; `authToken` and newer Socket options may need local type augmentation.

## Sources

### Primary (HIGH confidence)
- https://fal.ai/docs/documentation/model-apis/inference/queue — fetched; queue HTTP endpoints, headers, statuses, webhook param.
- https://fal.ai/models/minimax/h3-max/text-to-video/api — fetched; t2v input/output schema.
- https://fal.ai/api/openapi/queue/openapi.json?endpoint_id=minimax/h3-max/text-to-video — fetched; duration min/max, enums verbatim.
- https://fal.ai/models/minimax/h3-max/image-to-video/api — fetched; i2v schema, image_url aspect rule, end_image_url.
- https://fal.ai/models/minimax/h3-max/text-to-video — fetched; per-second pricing + promo end date.
- https://fal.ai/models/openrouter/router/api — fetched; router schema and usage/cost output.
- https://fal.ai/models/openrouter/router/vision/api — fetched; vision schema (image_urls optionality).
- https://fal.ai/models/fal-ai/flux-2-pro/api — fetched; FLUX schema incl. custom width/height quote.
- https://fal.ai/models/fal-ai/ffmpeg-api/extract-frame/api — fetched; frame_type enum, output.
- https://openrouter.ai/google/gemini-2.5-flash-lite — fetched; model existence, vision, context, pricing.
- https://fal-ex.hexdocs.pm/readme.html — fetched; fal_ex API surface and config.
- https://hex.pm/packages/fal_ex — fetched; 0.1.0, Jun 22 2025, 247 downloads, MIT.
- GitHub API repos/dantame/fal_ex — queried via gh; 6 commits, 0 stars, last push 2025-06-22.
- npm registry (registry.npmjs.org): phoenix 1.8.13 + exports map; @types/phoenix 1.6.7; @tanstack/react-router 1.170.32 + peerDeps/engines — queried directly.
- https://tanstack.com/router/latest/docs/framework/react/routing/code-based-routing — fetched; code-based API without plugin.
- https://phoenix.hexdocs.pm/js/index.html — fetched; JS Socket/Channel/Presence API, v1.8.13.
- https://phoenix.hexdocs.pm/Phoenix.Presence.html — fetched; server presence conventions.
- https://phoenix.hexdocs.pm/Phoenix.Endpoint.html — fetched; check_origin values and defaults.
- https://ecto-sql.hexdocs.pm/Ecto.Adapters.Postgres.html — fetched; :port option, default 5432.
- https://webkit.org/blog/6784/new-video-policies-for-ios/ — fetched; iOS autoplay rules verbatim.
- https://developer.chrome.com/blog/autoplay — fetched; Chrome autoplay/MEI rules.

### Secondary (MEDIUM confidence)
- fal webhooks `X-Fal-Webhook-Signature` header — WebSearch snippet referencing https://docs.fal.ai/model-apis/model-endpoints/webhooks (page itself 429'd on fetch).
- H3 Max 16:9/768P = 1344x768 @ 24fps — WebSearch snippet of fal pages, not fetched verbatim.
- ffmpeg-api pricing $0.0002/s — WebSearch snippet of the fal model page.
- image_urls accepting base64 data URIs — from the vision /api page summary; sentence not verbatim-quoted from schema.
- iOS `preload="auto"` ignored + `#t=0.001` workaround — multiple agreeing community sources (github.com/muxinc/elements/issues/963, github.com/videojs/video.js/discussions/9064, mux.com playback guide); no official Apple statement fetched.

### Tertiary (LOW confidence)
- Phoenix channel wire-protocol compatibility between npm 1.7.x client and 1.8 server — from memory of serializer stability; unverified against a doc.
- anikuku.com blog on H3 Max speed/pricing — surfaced in search, not fetched; do not rely on its latency claims.
