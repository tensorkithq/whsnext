import { createFileRoute } from "@tanstack/react-router";
import { Hud } from "../components/hud";
import { Stage } from "../components/stage";
import { VoteOverlay } from "../components/vote-overlay";
import { useEpisode } from "../lib/useEpisode";

export const Route = createFileRoute("/")({ component: EpisodePage });

/** The single live-episode screen; every piece reads from one store. */
function EpisodePage() {
  const episode = useEpisode();

  return (
    <div className="episode">
      <Stage
        phase={episode.phase}
        playback={episode.playback}
        preload={episode.preload}
        skewMs={episode.skewMs}
      />
      <Hud viewers={episode.viewers} />
      {episode.vote ? (
        <VoteOverlay
          vote={episode.vote}
          skewMs={episode.skewMs}
          castVote={episode.castVote}
        />
      ) : null}
      {!episode.connected ? <div className="connecting">Tuning in…</div> : null}
    </div>
  );
}
