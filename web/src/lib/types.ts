/** Wire protocol for the "episode:live" channel. Server is source of truth. */

export type Phase = "idle" | "opening" | "live" | "hold" | "ended";

export type PlaybackKind = "scene" | "bridge";

export interface Playback {
  kind: PlaybackKind;
  beat: number;
  /** Direct fal CDN URLs, one per 10s segment, in play order. */
  segments: string[];
  /** Server epoch ms when segment 0 started playing. */
  started_at_ms: number;
}

export interface VoteState {
  question: string;
  options: string[];
  tallies: number[];
  deadline_ms: number;
  locked: boolean;
  winner_idx: number | null;
  your_vote: number | null;
}

export interface EpisodeSync {
  phase: Phase;
  episode: { title: string; premise: string } | null;
  now_ms: number;
  playback: Playback | null;
  vote: VoteState | null;
}

export const SEGMENT_SECONDS = 10;
