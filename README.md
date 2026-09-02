# whn — realtime audience-controlled stories

A live story where everybody watching controls what happens next. One protagonist, one shared timeline: the audience votes, the winning choice becomes canon, and the next scene is generated on the fly. Think TikTok-style live vertical video crossed with Bandersnatch-style branching narrative, driven by realtime audience voting.

The stack: an Elixir/Phoenix server that runs episode processes, ingests votes over websockets, and orchestrates script generation (Celeris) and video generation (fal.ai); a React SPA in `web/` (TanStack Start) for the viewer experience; Postgres for persistence.

The launch property is **Lagos Wahala**, an interactive Nigerian-life comedy — see [PLOT.md](PLOT.md) for the plot and marketing brief. The technical brief lives further down in this document.

## Running the app

### Prerequisites

- **Nix** with flakes enabled. Everything else — Elixir, Node, Postgres, ffmpeg — comes from the devshell.
- **tmux** on the host. `app-start` runs the server inside a tmux session, and tmux is not part of the devshell.
- **API keys** for [fal.ai](https://fal.ai) (video generation) and Celeris (script generation). The server needs real keys to generate scenes.

Make sure `nix` itself is on your shell's `PATH` (it usually is; on some setups it lives in `/nix/var/nix/profiles/default/bin`). `app-start` resolves the `nix` binary from the environment and exits silently if it can't find it — see Troubleshooting.

### 1. Enter the devshell

```sh
nix develop
```

This puts Elixir, Node, Postgres, and the app lifecycle commands (`pg-start`, `app-start`, `logs`, …) on your `PATH`, and points Postgres at a local data directory (`.nix-postgres/`, port 57432).

### 2. Configure secrets

```sh
cp .env.example .env
```

Fill in `FAL_KEY` and `CELERIS_KEY`. The file is gitignored and sourced automatically every time the devshell starts (including the shell `app-start` launches for the server).

### 3. First-time setup

```sh
pg-start
(cd server && mix setup)   # deps, create DB, migrate, seed
```

Only needed once (or after a schema change).

### 4. Start the server

```sh
app-start
```

This starts Postgres if it isn't running, launches Phoenix in a tmux session named `whn-live`, waits for it to listen on `127.0.0.1:57400`, and then starts the seed episode (Lagos Wahala — "Salary Just Entered") in the server console.

Phoenix serves only the API and websocket — visiting `http://127.0.0.1:57400/` returns a 404 by design. The UI comes from the web client.

### 5. Run the web client

```sh
cd web
npm install
npm run dev
```

Open the URL Vite prints (`http://localhost:5173` by default). The dev server proxies `/api` and `/socket` to the Phoenix server on 57400.

For a production build: `npm run build`, then serve the output separately (`npm run preview` to check it locally).

### 6. Watch and vote

- Generation begins when the **first viewer** opens the web client — until then the episode idles and nothing is spent.
- Vote cycles need **at least 2 voters**; open two browser tabs if you're testing alone.
- Each 30-second scene cycle costs real money on fal.ai (roughly $2 at current pricing), so stop the server when you're done watching.

To watch the server itself:

```sh
tmux attach -t whn-live    # the live IEx console (detach with Ctrl-b d)
logs                       # tail Phoenix + Postgres logs (nix develop -c logs from outside the shell)
```

### 7. Stop

```sh
app-stop    # kills the tmux session and the BEAM on 57400
pg-stop     # shuts Postgres down
```

### Command reference

All defined in `flake.nix`, available inside `nix develop`:

| Command | What it does |
| --- | --- |
| `pg-start` | Init (first run) and start Postgres on `127.0.0.1:57432`, data in `.nix-postgres/` |
| `pg-stop` | Stop Postgres |
| `app-start` | Start Postgres if needed, launch Phoenix in tmux session `whn-live`, start the seed episode |
| `app-stop` | Kill the tmux session and any process listening on 57400 |
| `app-restart` | `app-stop` then `app-start` |
| `logs` | `tail -F` the Phoenix and Postgres logs |

### Running the server manually

If you'd rather skip tmux and drive the episode yourself:

```sh
pg-start
(cd server && iex -S mix phx.server)
```

```elixir
Whn.Episodes.start!(Whn.Seed.salary_just_entered())
```

`mix test` talks to the same Postgres, so keep `pg-start` running for the test suite too.

### Troubleshooting

- **`app-start` exits immediately with no output.** It resolves the `nix` binary with `command -v nix` under `set -e`, so if `nix` isn't on the `PATH` of the shell you launched `nix develop` from, the script dies before printing anything. Add nix's bin directory (often `/nix/var/nix/profiles/default/bin`) to your `PATH` and retry.
- **`http://127.0.0.1:57400/` returns 404.** Expected — the Phoenix server has no pages, only `/api` and `/socket`. Use the web client.
- **`app-start` reports "session died".** Inspect the crash with `tmux capture-pane -t whn-live -p` or `logs`.
- **Scenes never generate.** Check that `.env` has real `FAL_KEY` and `CELERIS_KEY` values, that at least one viewer has the web client open, and that two voters are present for vote cycles.

---

# Technical Brief — Realtime Interactive Story Platform

## 1. Product Objective

Build realtime interactive video entertainment where audience collectively decides what happens next to a protagonist.

Experience resembles:

**TikTok-style live video + Bandersnatch-style branching narrative + realtime audience voting.**

System must continuously convert audience decisions into next canonical video scene with minimal perceived generation delay.

---

## 2. Confirmed Product Loop

Each story progresses through repeated decision cycles.

### Current cycle

**1. Canonical scene plays — 30s**

At approximately **10s**, voting UI appears.

Audience receives approximately 3 options.

**2. Voting window — 10s**

Votes update live.

At approximately **20s**, voting locks.

Winning choice becomes canonical story direction.

**3. Remaining scene continues — 10s**

Current video continues while backend begins next-generation pipeline.

**4. Narrative bridge — 10–12s**

Bridge is not loading UI.

It is part of actual story: reaction, movement, dialogue, establishing action, suspense, etc.

Bridge must naturally connect current scene to winning continuation.

**5. Next 30s canonical scene begins**

Loop repeats.

---

## 3. Generation Strategy

### Confirmed

Generate **one winning continuation only**.

Do not generate all three voting branches speculatively by default.

This reduces video generation cost approximately 3× versus generating every option.

### Generation pipeline

After vote locks:

```text
vote winner
↓
Celeris updates story state
↓
Celeris produces bridge + winning continuation
↓
fal generates bridge
↓
extract final bridge frame
↓
use final frame as image input
↓
generate next canonical scene
↓
client preloads output
↓
scheduled playback
```

Important optimization:

Bridge generation should complete while remaining portion of current scene plays.

Because bridge exists before viewer reaches it, backend can extract its final frame and begin generating next scene while viewer is still watching:

```text
remaining current scene
+
bridge playback
=
generation latency budget
```

---

## 4. Video Generation

### Provider

**fal.ai**

### Model

**MiniMax H3 Max**

### Initial output

**480p**

Resolution prioritizes generation speed over fidelity for realtime experience.

### Scene construction

30s scenes may require multiple generation segments depending on model limits.

Continuity should use:

* previous bridge final frame
* protagonist identity
* wardrobe
* location
* lighting
* camera position
* characters present
* props
* emotional state
* winning decision
* current plot state

Where useful, generation can use image-to-video continuation from bridge endpoint.

---

## 5. Script Engine

### Model

**Celeris**

Celeris owns fast narrative reasoning between scenes.

Expected structured output:

```json
{
  "scene_summary": "",
  "winning_choice": "",
  "bridge": {
    "duration": 10,
    "script": "",
    "video_prompt": ""
  },
  "next_scene": {
    "duration": 30,
    "script": "",
    "video_prompt": ""
  },
  "next_choices": [],
  "story_state_updates": {}
}
```

Celeris should operate against explicit story state rather than regenerating context from transcript alone.

---

## 6. Story State

Each episode maintains canonical state including:

```text
episode
protagonist
supporting characters
location
time
money/resources
relationships
inventory/props
active problems
resolved events
unresolved events
personality/state variables
previous decisions
current objective
plot constraints
```

Votes modify canonical state.

Rejected options never become story truth.

---

## 7. Backend

### Confirmed stack

**Elixir + Phoenix**

Responsibilities:

* WebSocket connections
* episode rooms
* audience presence
* vote ingestion
* vote aggregation
* countdown synchronization
* canonical decision locking
* episode state
* Celeris orchestration
* fal orchestration
* generation lifecycle
* client broadcasts
* playback synchronization
* failure recovery

### Realtime model

Prefer one supervised episode process per live episode.

Conceptually:

```text
EpisodeProcess
├── current scene
├── current story state
├── vote options
├── vote counts
├── voting deadline
├── winning branch
├── bridge generation
└── next-scene generation
```

Phoenix PubSub handles audience fan-out.

---

## 8. Frontend

### Stack

**React**

Primary experience is vertical, mobile-first video UI.

Core components:

```text
VideoPlayer
VoteOverlay
LiveVoteCount
Countdown
Comments
EpisodeProgress
UpcomingEpisodeCountdown
Share
```

UI should feel closer to TikTok than traditional game UI.

Video remains dominant surface.

---

## 9. Video Delivery

Backend should not proxy video bytes.

Preferred:

```text
fal-generated video
↓
direct asset URL
↓
client preload
↓
local video player
```

Client should maintain:

```text
activePlayer
standbyPlayer
```

Standby player preloads next canonical clip.

At scene boundary, players swap.

CDN infrastructure is deferred unless later required for economics, retention, performance, or ownership.

---

## 10. Anonymous Identity

V1 does not require account creation.

On first visit:

```text
crypto.randomUUID()
↓
localStorage
↓
anonymous user ID
```

ID accompanies WebSocket and HTTP interactions.

Use cases:

* one-vote-per-local-identity controls
* lightweight history
* engagement analytics
* result persistence
* future account migration

This is identity continuity, not secure authentication.

Users may reset identity by clearing browser storage.

Device fingerprinting is out of scope.

Google OAuth can be introduced later.

---

## 11. Persistence

### Postgres

Durable source for:

* episodes
* plots
* scenes
* choices
* winning decisions
* anonymous users
* vote results
* story state snapshots
* generation metadata
* generated asset URLs
* episode analytics

### Redis

Not required initially.

Add only if concrete requirements emerge for distributed caching, rate limiting, external queues, counters, or cross-service coordination.

---

## 12. Failure Handling

System must gracefully handle:

**Video not ready**

Continue bridge where possible, extend with approved fallback content, or display brief narrative-safe hold state.

**Generation failure**

Retry generation with idempotency guard.

**Celeris failure**

Retry structured generation without reopening vote.

**Viewer reconnect**

Client receives current canonical scene, playback timestamp, current vote state, and deadline.

**Duplicate vote**

Episode process applies voting policy using anonymous identity.

**Backend restart**

Persist enough episode state to reconstruct current canonical timeline.

---

## 13. Launch Cadence

**Confirmed: 5 episodes/day.**

Each episode is an independent live plot/session.

Episode duration: **TBD**

Candidates:

* 15 minutes
* 30 minutes
* 60 minutes

Initial recommendation for validation: **15–30 minutes**.

Five sessions/day creates scarcity while producing enough repeated sessions to test retention, concurrency, plot quality, voting behavior, and generation reliability.

---

## 14. Open Decisions

1. 15, 30, or 60-minute episode duration.
2. Default bridge length: 10s or 12s.
3. Whether bridge duration dynamically expands when next scene is late.
4. Comments implementation at launch.
5. Maximum simultaneous audience.
6. Vote manipulation policy.
7. Whether viewers joining midway can vote immediately.
8. Generated-video retention period.
9. Whether protagonist persists across episodes or resets per plot.
10. Exact synchronization tolerance between viewers.

---

## 15. MVP Success Condition

V1 succeeds technically when audience can watch one uninterrupted episode where:

**video → vote → canonical decision → generated continuation**

repeats reliably without viewer experiencing generation as an explicit loading state.
