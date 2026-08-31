import { useEffect, useRef, useState } from "react";
import { Channel, Presence, Socket } from "phoenix";
import { anonId } from "./identity";
import type { EpisodeSync, Phase, Playback, VoteState } from "./types";

export interface EpisodeStore {
  connected: boolean;
  phase: Phase;
  episode: { title: string; premise: string } | null;
  playback: Playback | null;
  /** URLs the standby player should warm before they go live. */
  preload: string[];
  vote: VoteState | null;
  viewers: number;
  /** Add to Date.now() to get server time. */
  skewMs: number;
  castVote: (optionIdx: number) => void;
}

/** One socket + one channel; every server broadcast lands in this store. */
export function useEpisode(): EpisodeStore {
  const [connected, setConnected] = useState(false);
  const [phase, setPhase] = useState<Phase>("idle");
  const [episode, setEpisode] = useState<EpisodeStore["episode"]>(null);
  const [playback, setPlayback] = useState<Playback | null>(null);
  const [preload, setPreload] = useState<string[]>([]);
  const [vote, setVote] = useState<VoteState | null>(null);
  const [viewers, setViewers] = useState(1);
  const [skewMs, setSkewMs] = useState(0);
  const channelRef = useRef<Channel | null>(null);

  useEffect(() => {
    const socket = new Socket("/socket", { params: { anon_id: anonId() } });
    socket.connect();

    const channel = socket.channel("episode:live", {});
    channelRef.current = channel;

    const presence = new Presence(channel);
    presence.onSync(() => setViewers(Math.max(1, presence.list().length)));

    channel.on("phase", (msg: { phase: Phase }) => setPhase(msg.phase));
    channel.on("playback", (msg: Playback) => {
      setPlayback(msg);
      setPreload([]);
    });
    channel.on("preload", (msg: { urls: string[] }) => setPreload(msg.urls));
    channel.on("vote_open", (msg: VoteState) => setVote(msg));
    channel.on("vote_update", (msg: { tallies: number[] }) =>
      setVote((v) => (v ? { ...v, tallies: msg.tallies } : v))
    );
    channel.on(
      "vote_locked",
      (msg: { winner_idx: number; tallies: number[] }) =>
        setVote((v) =>
          v
            ? {
                ...v,
                locked: true,
                winner_idx: msg.winner_idx,
                tallies: msg.tallies,
              }
            : v
        )
    );
    channel.on("vote_closed", () => setVote(null));

    channel
      .join()
      .receive("ok", (sync: EpisodeSync) => {
        setConnected(true);
        setSkewMs(sync.now_ms - Date.now());
        setPhase(sync.phase);
        setEpisode(sync.episode);
        setPlayback(sync.playback);
        setVote(sync.vote);
      })
      .receive("error", () => setConnected(false));

    return () => {
      channel.leave();
      socket.disconnect();
      channelRef.current = null;
    };
  }, []);

  const castVote = (optionIdx: number) => {
    channelRef.current
      ?.push("vote", { option_idx: optionIdx })
      .receive("ok", (msg: { tallies: number[]; your_vote: number }) =>
        setVote((v) =>
          v ? { ...v, tallies: msg.tallies, your_vote: msg.your_vote } : v
        )
      );
  };

  return {
    connected,
    phase,
    episode,
    playback,
    preload,
    vote,
    viewers,
    skewMs,
    castVote,
  };
}
