# Realtime

## The server clock is the source of truth

Send deadlines as absolute epoch milliseconds from the server. Client device clocks are skewed, so relative timers drift between viewers.

## Server time is not what the viewer sees

The server opened the vote ten seconds into the scene on its own clock. A buffering client was still behind, so the poll appeared before the moment it belonged to.

Fix: publish the real playback position from the player, segment index times segment length plus `currentTime`. Show the vote card only once playback reaches the vote offset. Keep a deadline floor so a lagging viewer still gets a usable window. Countdown and lock stay on server time; only visibility follows playback.

## Back-to-back broadcasts hide state

The lock broadcast and the close went out together. The client tore the poll down before anyone saw the winner.

Fix: schedule the close after a short reveal delay. The close handler only acts on a vote that is still locked, so a duplicate or late close falls through harmlessly.

## Reconnects should cost one round-trip

On join, reply with a full snapshot: phase, server clock, playback position, and the viewer's own vote. A reconnecting client recovers from that alone.

## Gate expensive work on presence

Do not start paid generation with zero viewers. Park the cycle and resume it when Presence reports viewers again.

## Votes are immutable per viewer

First write wins. A duplicate vote replies ok with the original pick. A unique index in the database backs this up if the in-memory check is bypassed.
