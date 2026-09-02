import { useEffect, useState } from "react";
import type { VoteState } from "../lib/types";
import { playhead } from "../lib/playhead";

/** The server opens the vote 10s into the scene; reveal just shy of it. */
const GATE_OFFSET_S = 9.5;
/** Never squeeze a lagging viewer's window below this much of the deadline. */
const GATE_FLOOR_MS = 7_000;

/**
 * The server broadcasts vote_open on its own clock, but a buffering client
 * may be visually behind — showing the poll then spoils a moment the viewer
 * hasn't reached. Hold the card until the picture catches up, with a
 * deadline floor so a badly lagged viewer still gets a usable window.
 */
function gateOpen(vote: VoteState, skewMs: number) {
  if (vote.your_vote !== null || vote.locked) return true;
  if (vote.deadline_ms - (Date.now() + skewMs) <= GATE_FLOOR_MS) return true;
  return playhead.kind === "scene" && playhead.seconds >= GATE_OFFSET_S;
}

/**
 * Instagram-story poll in the lower third. Pills until you commit, then
 * live percentage bars; the winner lights up at lock. The parent only
 * mounts this while a vote exists, so vote_closed tears it down and a
 * stale vote_update can't resurrect it.
 */
export function VoteOverlay({
  vote,
  skewMs,
  castVote,
}: {
  vote: VoteState;
  skewMs: number;
  castVote: (optionIdx: number) => void;
}) {
  const [visible, setVisible] = useState(() => gateOpen(vote, skewMs));

  useEffect(() => {
    if (visible) return;
    const timer = setInterval(() => {
      if (gateOpen(vote, skewMs)) setVisible(true);
    }, 250);
    return () => clearInterval(timer);
  }, [visible, vote, skewMs]);

  const revealed = vote.your_vote !== null || vote.locked;
  const totalVotes = vote.tallies.reduce((sum, n) => sum + n, 0);

  if (!visible) return null;

  return (
    <div className="poll">
      <div className="poll-card">
        <div className="poll-question">{vote.question}</div>
        <div className="poll-options">
          {vote.options.map((option, idx) => {
            if (!revealed) {
              return (
                <button
                  key={option}
                  type="button"
                  className="poll-pill"
                  onClick={() => castVote(idx)}
                >
                  {option}
                </button>
              );
            }
            const pct = Math.round(
              ((vote.tallies[idx] ?? 0) / Math.max(1, totalVotes)) * 100
            );
            const winner = vote.locked && vote.winner_idx === idx;
            return (
              <div
                key={option}
                className={`poll-bar${winner ? " winner" : ""}`}
              >
                <div className="poll-fill" style={{ width: `${pct}%` }} />
                <span className="poll-option-label">
                  {option}
                  {vote.your_vote === idx ? (
                    <span className="poll-check"> ✓</span>
                  ) : null}
                </span>
                <span className="poll-pct">{pct}%</span>
              </div>
            );
          })}
        </div>
        <Countdown
          key={vote.deadline_ms}
          deadlineMs={vote.deadline_ms}
          skewMs={skewMs}
        />
      </div>
    </div>
  );
}

/** rAF countdown against the server clock: seconds plus a shrinking track. */
function Countdown({
  deadlineMs,
  skewMs,
}: {
  deadlineMs: number;
  skewMs: number;
}) {
  const [now, setNow] = useState(() => Date.now());
  const [totalMs] = useState(() =>
    Math.max(deadlineMs - (Date.now() + skewMs), 1)
  );

  useEffect(() => {
    let frame = requestAnimationFrame(function tick() {
      setNow(Date.now());
      frame = requestAnimationFrame(tick);
    });
    return () => cancelAnimationFrame(frame);
  }, []);

  const remaining = Math.max(0, deadlineMs - (now + skewMs));
  const pct = Math.min(100, (remaining / totalMs) * 100);
  const seconds = Math.ceil(remaining / 1000);
  const urgent = remaining < 3_000;

  return (
    <div className="countdown">
      <div className="countdown-track">
        <div
          className={`countdown-fill${urgent ? " urgent" : ""}`}
          style={{ width: `${pct}%` }}
        />
      </div>
      <span className={`countdown-num${urgent ? " urgent" : ""}`}>
        {seconds}s
      </span>
    </div>
  );
}
