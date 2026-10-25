const BUCKET_MS = 5 * 60 * 1000;

export function customWindowBounds(range) {
    const start = new Date(range?.start).getTime();
    const stop = new Date(range?.stop).getTime();
    return Number.isFinite(start) && Number.isFinite(stop) && stop > start
        ? { start, stop, ms: stop - start }
        : null;
}

export function historyWindowBounds({ now, span, offset = 0 }) {
    const bottom = now - Math.max(0, offset);
    const padding = offset > 1000
        ? Math.min(BUCKET_MS, Math.max(30000, span * 0.1))
        : 10000;
    // Socket updates move the chart while query boundaries stay stable.
    return {
        start: new Date(Math.floor((bottom - span - padding) / BUCKET_MS) * BUCKET_MS).toISOString(),
        stop: new Date(Math.ceil((bottom + padding) / BUCKET_MS) * BUCKET_MS).toISOString()
    };
}
