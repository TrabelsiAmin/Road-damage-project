import { describe, it, expect } from 'vitest';
import { THEME_STORAGE_KEY, getInitialTheme, resolveNextTheme } from './theme';

describe('Theme State Utilities', () => {
  it('reads saved theme preference from storage', () => {
    const mockStorage = {
      store: { [THEME_STORAGE_KEY]: 'dark' },
      getItem(key) {
        return this.store[key] || null;
      },
      setItem(key, val) {
        this.store[key] = val;
      },
    };

    expect(getInitialTheme(mockStorage, false)).toBe('dark');

    mockStorage.store[THEME_STORAGE_KEY] = 'light';
    expect(getInitialTheme(mockStorage, true)).toBe('light');
  });

  it('falls back to prefersDark if storage is empty or throws', () => {
    const emptyStorage = {
      getItem: () => null,
    };
    expect(getInitialTheme(emptyStorage, true)).toBe('dark');
    expect(getInitialTheme(emptyStorage, false)).toBe('light');

    const failingStorage = {
      getItem: () => {
        throw new Error('Access denied');
      },
    };
    expect(getInitialTheme(failingStorage, true)).toBe('dark');
    expect(getInitialTheme(failingStorage, false)).toBe('light');
    expect(getInitialTheme(null, false)).toBe('light');
  });

  it('correctly toggles between dark and light themes', () => {
    expect(resolveNextTheme('light')).toBe('dark');
    expect(resolveNextTheme('dark')).toBe('light');
  });
});
