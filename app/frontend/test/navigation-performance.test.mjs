import { test } from 'node:test';
import assert from 'node:assert/strict';
import { historyWindowBounds, customWindowBounds } from '../src/components/EDR/historyWindow.js';
import { lazyWithRetry } from '../src/lazyWithRetry.js';

test('live ticks reuse history bounds instead of restarting every second', () => {
    const now = Date.parse('2026-10-17T10:02:00Z');
    for (const span of [60000, 300000, 3600000, 86400000]) {
        const first = historyWindowBounds({ now, span });
        for (let seconds = 1; seconds < 60; seconds++) {
            assert.deepEqual(historyWindowBounds({ now: now + seconds * 1000, span }), first);
        }
        assert.ok(Date.parse(first.start) <= now - span);
        assert.ok(Date.parse(first.stop) >= now);
    }
});

test('scrollback and longer selections fetch the entire visible range', () => {
    const now = Date.parse('2026-10-17T10:02:00Z');
    for (const span of [60000, 1800000, 86400000, 7 * 86400000]) {
        for (const offset of [0, 3600000, 30 * 86400000]) {
            const bounds = historyWindowBounds({ now, span, offset });
            assert.ok(Date.parse(bounds.start) <= now - offset - span);
            assert.ok(Date.parse(bounds.stop) >= now - offset);
        }
    }
});

test('custom RFC3339 ranges produce numeric chart bounds and duration', () => {
    const bounds = customWindowBounds({ start: '2026-10-16T09:30:00+05:30', stop: '2026-10-16T10:30:00+05:30' });
    assert.equal(bounds.ms, 3600000);
    assert.equal(bounds.stop - bounds.start, bounds.ms);
    for (const range of [null, {}, { start: 'bad', stop: 'bad' }, { start: '2026-10-17', stop: '2026-10-16' }]) {
        assert.equal(customWindowBounds(range), null);
    }
});

test('page preloading deduplicates imports and never reloads on a background failure', async () => {
    const entries = new Map();
    globalThis.sessionStorage = { removeItem: key => entries.delete(key), getItem: key => entries.get(key), setItem: (key, value) => entries.set(key, value) };
    let reloads = 0;
    globalThis.window = { location: { reload: () => { reloads++; } } };
    let calls = 0;
    const page = lazyWithRetry(async () => { calls++; return { default: () => null }; }, 'test-success');
    await Promise.all([page.preload(), page.preload(), page.preload()]);
    assert.equal(calls, 1);
    let attempts = 0;
    const failing = lazyWithRetry(async () => {
        attempts++;
        if (attempts === 1) throw new Error('Failed to fetch dynamically imported module');
        return { default: () => null };
    }, 'test-failure');
    await assert.rejects(failing.preload());
    await failing.preload();
    assert.equal(attempts, 2);
    assert.equal(reloads, 0);
});

