import { describe, it, expect } from 'vitest';
import { getInitialTheme, persistTheme, resolveNextTheme } from './theme';

function storageWith(value) {
  return {
    getItem(key) {
      return key === 'tariqmap_theme' ? value : null;
    },
  };
}

describe('Theme State Utilities', () => {
  it('restores a stored dark or light choice', () => {
    expect(getInitialTheme(storageWith('dark'), false)).toBe('dark');
    expect(getInitialTheme(storageWith('light'), true)).toBe('light');
  });

  it('follows the system preference only when nothing valid is stored', () => {
    expect(getInitialTheme(storageWith(null), true)).toBe('dark');
    expect(getInitialTheme(storageWith(null), false)).toBe('light');
    expect(getInitialTheme(storageWith('sepia'), true)).toBe('dark');
    expect(getInitialTheme(storageWith('sepia'), false)).toBe('light');
  });

  it('falls back safely when storage throws or is missing', () => {
    expect(getInitialTheme({
      getItem() {
        throw new Error('Access denied');
      },
    }, true)).toBe('dark');
    expect(getInitialTheme(null, false)).toBe('light');
    expect(getInitialTheme(undefined, true)).toBe('dark');
  });

  it('toggles between light and dark', () => {
    expect(resolveNextTheme('light')).toBe('dark');
    expect(resolveNextTheme('dark')).toBe('light');
    expect(resolveNextTheme('other')).toBe('dark');
  });

  it('persists an explicit choice and survives a storage failure', () => {
    const store = {};
    const storage = {
      setItem(key, value) {
        store[key] = value;
      },
      getItem(key) {
        return Object.prototype.hasOwnProperty.call(store, key) ? store[key] : null;
      },
    };

    expect(persistTheme('dark', storage)).toBe('dark');
    expect(getInitialTheme(storage, false)).toBe('dark');
    expect(persistTheme('light', {
      setItem() {
        throw new Error('quota');
      },
    })).toBe('light');
    expect(persistTheme('dark', null)).toBe('dark');
  });
});
