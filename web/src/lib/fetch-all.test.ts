import { describe, expect, it } from 'vitest';
import { fetchAllRows } from './fetch-all';

const source = Array.from({ length: 2345 }, (_, i) => i);
const pager = (calls: [number, number][]) => (from: number, to: number) => {
  calls.push([from, to]);
  return Promise.resolve({ data: source.slice(from, to + 1), error: null });
};

describe('fetchAllRows', () => {
  it('reads every page past the 1000-row cap', async () => {
    const calls: [number, number][] = [];
    const rows = await fetchAllRows(pager(calls));
    expect(rows).toEqual(source);
    expect(calls).toEqual([[0, 999], [1000, 1999], [2000, 2999]]);
  });

  it('stops after one request when the first page is short', async () => {
    const calls: [number, number][] = [];
    await fetchAllRows(pager(calls), 5000);
    expect(calls).toHaveLength(1);
  });

  it('throws the query error', async () => {
    const err = new Error('boom');
    await expect(fetchAllRows(() => Promise.resolve({ data: null, error: err }))).rejects.toBe(err);
  });
});
