import { describe, it, expect } from 'vitest';
import { getInitialTheme, resolveNextTheme } from './theme';

describe('Theme State Utilities', () => {
  it('stays light even when a dark preference was stored', () => {
    const mockStorage = {
      store: { tariqmap_theme: 'dark' },
      getItem(key) {
        return this.store[key] || null;
      },
    };

    expect(getInitialTheme(mockStorage, false)).toBe('light');
    expect(getInitialTheme(mockStorage, true)).toBe('light');
  });

  it('stays light when storage is empty or throws', () => {
    expect(getInitialTheme({ getItem: () => null }, true)).toBe('light');
    expect(getInitialTheme({ getItem: () => null }, false)).toBe('light');
    expect(getInitialTheme({
      getItem() {
        throw new Error('Access denied');
      },
    }, true)).toBe('light');
    expect(getInitialTheme(null, false)).toBe('light');
  });

  it('does not switch into a dark theme', () => {
    expect(resolveNextTheme('light')).toBe('light');
    expect(resolveNextTheme('dark')).toBe('light');
  });
});
