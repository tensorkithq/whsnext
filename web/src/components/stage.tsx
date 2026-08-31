import { useEffect, useRef, useState } from "react";
import type { Phase, Playback } from "../lib/types";
import { SEGMENT_SECONDS } from "../lib/types";

const SEGMENT_MS = SEGMENT_SECONDS * 1000;

/** Where the server clock says playback is right now. */
function locate(playback: Playback, skewMs: number) {
  const elapsed = Date.now() + skewMs - playback.started_at_ms;
  const last = playback.segments.length - 1;
  const idx = Math.min(Math.max(Math.floor(elapsed / SEGMENT_MS), 0), last);
  const offsetSec = Math.min(
    Math.max((elapsed - idx * SEGMENT_MS) / 1000, 0),
    SEGMENT_SECONDS
  );
  return { idx, offsetSec };
}

/** `#t=` media fragment: native seek-on-load, and iOS paints the first frame. */
function fragmentSrc(url: string, offsetSec = 0) {
  if (offsetSec <= 0.001) return `${url}#t=0.001`;
  return `${url}#t=${offsetSec.toFixed(3)}`;
}

/**
 * Full-bleed vertical theater: two stacked <video> elements, one live and
 * one warming the next clip, swapped at segment boundaries so the seam
 * never shows. The server clock (started_at_ms + skew) is the only
 * authority on what should be on screen; local playback events never
 * advance protocol state.
 */
export function Stage({
  phase,
  playback,
  preload,
  skewMs,
}: {
  phase: Phase;
  playback: Playback | null;
  preload: string[];
  skewMs: number;
}) {
  const playerA = useRef<HTMLVideoElement>(null);
  const playerB = useRef<HTMLVideoElement>(null);
  const players = [playerA, playerB] as const;

  const [activeIdx, setActiveIdx] = useState<0 | 1>(0);
  const activeRef = useRef<0 | 1>(0);
  const [segIdx, setSegIdx] = useState(0);
  const [started, setStarted] = useState(false);
  const startedRef = useRef(false);

  const setActive = (idx: 0 | 1) => {
    activeRef.current = idx;
    setActiveIdx(idx);
  };

  // Sync to server truth whenever playback (re)arrives: seek the active
  // player into the segment the clock says is live.
  useEffect(() => {
    if (!playback) return;
    const { idx, offsetSec } = locate(playback, skewMs);
    const url = playback.segments[idx];
    const el = players[activeRef.current].current;
    if (!url || !el) return;
    el.src = fragmentSrc(url, offsetSec);
    setSegIdx(idx);
    if (startedRef.current) {
      el.muted = false;
      el.play().catch(() => {});
    }
  }, [playback, skewMs]);

  // Warm the standby with whatever comes next: the following segment of
  // this clip, or the preloaded next clip once the server announces it.
  useEffect(() => {
    const nextUrl = playback?.segments[segIdx + 1] ?? preload[0];
    if (!nextUrl) return;
    const el = players[activeRef.current === 0 ? 1 : 0].current;
    if (!el || el.src.startsWith(nextUrl)) return;
    el.muted = true;
    el.src = fragmentSrc(nextUrl);
    el.play()
      .then(() => el.pause())
      .catch(() => {});
  }, [playback, preload, segIdx]);

  // Hold: freeze on the last available frame; the shimmer overlay does the
  // talking until the next playback broadcast resumes us.
  useEffect(() => {
    if (phase !== "hold") return;
    playerA.current?.pause();
    playerB.current?.pause();
  }, [phase]);

  // Local segment boundary: promote the warmed standby. Protocol state
  // (phase, playback) only ever moves via server broadcast.
  const handleEnded = (ended: 0 | 1) => {
    if (ended !== activeRef.current || !playback) return;
    const next = segIdx + 1;
    const url = playback.segments[next];
    if (!url) return;
    const standby: 0 | 1 = ended === 0 ? 1 : 0;
    const el = players[standby].current;
    if (!el) return;
    if (!el.src.startsWith(url)) el.src = fragmentSrc(url);
    setActive(standby);
    setSegIdx(next);
    if (startedRef.current) {
      el.muted = false;
      el.play().catch(() => {});
    }
  };

  // Mobile autoplay gate: nothing plays until this tap. The gesture
  // unlocks both elements, unmutes the active one, and re-seeks to the
  // server clock (time kept moving while we waited).
  const handleStart = () => {
    startedRef.current = true;
    setStarted(true);
    const el = players[activeRef.current].current;
    const standby = players[activeRef.current === 0 ? 1 : 0].current;
    if (el && playback) {
      const { idx, offsetSec } = locate(playback, skewMs);
      const url = playback.segments[idx];
      if (url) {
        el.src = fragmentSrc(url, offsetSec);
        setSegIdx(idx);
      }
      el.muted = false;
      el.play().catch(() => {});
    }
    standby
      ?.play()
      .then(() => standby.pause())
      .catch(() => {});
  };

  return (
    <div className="stage">
      <video
        ref={playerA}
        className={`stage-video${activeIdx === 0 ? " active" : ""}`}
        muted
        playsInline
        preload="auto"
        onEnded={() => handleEnded(0)}
      />
      <video
        ref={playerB}
        className={`stage-video${activeIdx === 1 ? " active" : ""}`}
        muted
        playsInline
        preload="auto"
        onEnded={() => handleEnded(1)}
      />
      <div className="scrim scrim-top" />
      <div className="scrim scrim-bottom" />
      {phase === "hold" ? (
        <div className="hold-shimmer" aria-hidden="true" />
      ) : null}
      {!started ? (
        <button type="button" className="tap-gate" onClick={handleStart}>
          <span className="tap-gate-icon">▶</span>
          <span className="tap-gate-label">Tap to watch</span>
        </button>
      ) : null}
    </div>
  );
}
