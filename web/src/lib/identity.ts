const KEY = "whn:anon-id";

/** Anonymous identity per the brief: continuity, not authentication. */
export function anonId(): string {
  try {
    const existing = localStorage.getItem(KEY);
    if (existing) return existing;
    const id = crypto.randomUUID();
    localStorage.setItem(KEY, id);
    return id;
  } catch {
    return crypto.randomUUID();
  }
}
