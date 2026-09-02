/**
 * Live visual position of the stage: what the viewer's eyes are actually
 * seeing, as opposed to the server clock. Written by <Stage/> (mutated, no
 * re-renders), read by overlays that must not run ahead of the picture —
 * the vote card most of all.
 */
export const playhead = {
  kind: "" as "" | "scene" | "bridge",
  beat: -1,
  /** Seconds into the current playback unit (segment index × 10 + currentTime). */
  seconds: 0,
};
