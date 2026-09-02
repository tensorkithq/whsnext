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

---

## Development

This branch (`gen/wordless`) is the wordless-audio variant: no character ever speaks — expressive wordless voices over ambient audio and score.

Everything runs inside the Nix devshell (Elixir, Node, ffmpeg, Postgres).

```sh
nix develop            # enter the devshell
pg-start               # Postgres on 127.0.0.1:57432 (data in .nix-postgres/)
cp .env.example .env   # then fill in FAL_KEY (gitignored, auto-sourced by the shell)
(cd server && mix setup)         # deps, create DB, migrate, seed
(cd server && mix phx.server)    # API on 127.0.0.1:57400
(cd web && npm install && npm run dev)   # UI on the Vite port, proxies /socket and /api to 57400
```

Notes:

- Postgres listens on 57432, not 5432; the port is pinned in the server config, so no env vars needed.
- `mix test` talks to the same Postgres — keep `pg-start` running.
- `pg-stop` shuts Postgres down when you're done.

### Start the live episode

With Postgres up and both `FAL_KEY` and `CELERIS_KEY` filled in `.env`, boot an
interactive server and start the seed episode (Lagos Wahala — "Salary Just Entered"):

```sh
(cd server && iex -S mix phx.server)
```

```elixir
Whn.Episodes.start!(Whn.Seed.salary_just_entered())
```

Generation waits until at least one viewer has the web client open, then calls
fal for real: each 30-second scene cycle costs about $2.00 at post-promo
pricing. Stop the server when you're done watching.
