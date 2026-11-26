// Fixed-window request counters, kept in memory only: a restart forgets
// them, and nothing about who asked ever reaches the disk.

type Window = { start: number; count: number };

/** Gives back a request that was counted but did not happen. */
export type Refund = () => void;

export class RateLimit {
  // Insertion order is window start order, so the oldest windows come first.
  private readonly windows = new Map<string, Window>();
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

  /**
   * Counts a request under `key` and answers how to give it back; undefined,
   * and not counted, once the window's limit is spent.
   */
  allow(key: string): Refund | undefined {
    const now = this.now();
    const live = this.windows.get(key);
    if (live && now - live.start < this.windowMs) {
      if (live.count >= this.limit) return undefined;
      live.count += 1;
      return this.refund(key, live);
    }
    this.windows.delete(key);
    this.prune(now);
    const window = { start: now, count: 1 };
    this.windows.set(key, window);
    return this.refund(key, window);
  }

  /** Refunds only into the window that counted the request. */
  private refund(key: string, window: Window): Refund {
    return () => {
      if (this.windows.get(key) === window) window.count -= 1;
    };
  }

  /** Drops expired windows, then the oldest live ones while the map is full. */
  private prune(now: number): void {
    for (const [key, window] of this.windows) {
      if (now - window.start < this.windowMs && this.windows.size < this.capacity) return;
      this.windows.delete(key);
    }
  }
}
