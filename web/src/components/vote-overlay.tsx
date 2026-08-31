import { useEffect, useState } from "react";
import type { VoteState } from "../lib/types";

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
  const revealed = vote.your_vote !== null || vote.locked;
  const totalVotes = vote.tallies.reduce((sum, n) => sum + n, 0);

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
