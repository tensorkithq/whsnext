/** Top chrome: LIVE badge on the left, Presence viewer count on the right. */
export function Hud({ viewers }: { viewers: number }) {
  return (
    <div className="hud">
      <span className="live-badge">LIVE</span>
      <span className="viewer-count">{viewers} watching</span>
    </div>
  );
}
