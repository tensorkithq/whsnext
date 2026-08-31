import { createFileRoute } from "@tanstack/react-router";
import { useEpisode } from "../lib/useEpisode";

export const Route = createFileRoute("/")({ component: EpisodePage });

/** The single live-episode screen; every piece reads from one store. */
function EpisodePage() {
  const episode = useEpisode();

  return (
    <div className="episode">
      {!episode.connected && <div className="connecting">Tuning in…</div>}
    </div>
  );
}
