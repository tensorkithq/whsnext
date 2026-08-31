import { createFileRoute } from "@tanstack/react-router";
import { Stage } from "../components/stage";
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
      {!episode.connected ? <div className="connecting">Tuning in…</div> : null}
    </div>
  );
}
