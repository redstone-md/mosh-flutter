// Fixed-window request counters, kept in memory only: a restart forgets
// them, and nothing about who asked ever reaches the disk.

export class RateLimit {
  // Insertion order is window start order, so the oldest windows come first.
  private readonly windows = new Map<string, { start: number; count: number }>();
  private readonly limit: number;
  private readonly windowMs: number;
  private readonly now: () => number;
  private readonly capacity: number;

  constructor(limit: number, windowMs: number, now: () => number, capacity = 100_000) {
    this.limit = limit;
    this.windowMs = windowMs;
    this.now = now;
    this.capacity = capacity;
  }

  /** Counts a request under `key`; false, and not counted, once the window's limit is spent. */
  allow(key: string): boolean {
    const now = this.now();
    const window = this.windows.get(key);
    if (window && now - window.start < this.windowMs) {
      if (window.count >= this.limit) return false;
      window.count += 1;
      return true;
    }
    this.windows.delete(key);
    this.prune(now);
    this.windows.set(key, { start: now, count: 1 });
    return true;
  }

  /** Gives back a request `allow` counted that did not happen. */
  refund(key: string): void {
    const window = this.windows.get(key);
    if (window && window.count > 0) window.count -= 1;
  }

  /** Drops expired windows, then the oldest live ones while the map is full. */
  private prune(now: number): void {
    for (const [key, window] of this.windows) {
      if (now - window.start < this.windowMs && this.windows.size < this.capacity) return;
      this.windows.delete(key);
    }
  }
}
