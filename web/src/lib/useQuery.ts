'use client';

import { useCallback, useEffect, useRef, useState } from 'react';

interface QueryState<T> {
  key: string;
  data: T;
}

export interface QueryResult<T> {
  /** Latest data, or `initialData` until the first fetch resolves. */
  data: T | undefined;
  /** True until data is available for the first time. */
  loading: boolean;
  /** True while a refetch (key change or reload) is in flight. */
  refreshing: boolean;
  error: unknown;
  /** Refetch with the same key. */
  reload: () => void;
  /** Optimistically update the cached data. */
  mutate: (updater: (data: T) => T) => void;
}

/**
 * Minimal data-fetching hook: runs `fetcher` whenever `key` changes or
 * `reload()` is called, ignores stale responses, and can start from cached
 * `initialData` so pages render instantly.
 */
export function useQuery<T>(key: string, fetcher: () => Promise<T>, initialData?: T): QueryResult<T> {
  const [state, setState] = useState<QueryState<T> | null>(() =>
    initialData !== undefined ? { key: '', data: initialData } : null,
  );
  const [error, setError] = useState<unknown>(null);
  const [version, setVersion] = useState(0);
  const fetcherRef = useRef(fetcher);

  useEffect(() => {
    fetcherRef.current = fetcher;
  });

  const requestKey = `${key}#${version}`;

  useEffect(() => {
    let cancelled = false;
    fetcherRef.current().then(
      (data) => {
        if (cancelled) return;
        setState({ key: requestKey, data });
        setError(null);
      },
      (err) => {
        if (cancelled) return;
        console.error('Query failed:', err);
        setError(err);
        // Stop showing a spinner forever when the very first request fails.
        setState((prev) => prev ?? null);
      },
    );
    return () => {
      cancelled = true;
    };
  }, [requestKey]);

  const reload = useCallback(() => setVersion((v) => v + 1), []);
  const mutate = useCallback((updater: (data: T) => T) => {
    setState((prev) => (prev ? { ...prev, data: updater(prev.data) } : prev));
  }, []);

  return {
    data: state?.data,
    loading: state === null && !error,
    refreshing: state !== null && state.key !== requestKey,
    error,
    reload,
    mutate,
  };
}

/** Reads a JSON value cached in localStorage, tolerating missing/corrupt data. */
export function readCache<T>(key: string): T | undefined {
  if (typeof window === 'undefined') return undefined;
  try {
    const raw = window.localStorage.getItem(key);
    return raw ? (JSON.parse(raw) as T) : undefined;
  } catch {
    return undefined;
  }
}

export function writeCache(key: string, value: unknown): void {
  try {
    window.localStorage.setItem(key, JSON.stringify(value));
  } catch {
    // storage full or unavailable: caching is best-effort
  }
}
