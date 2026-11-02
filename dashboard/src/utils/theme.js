/**
 * Theme management utilities for TariqMap Dashboard (Dark / Light mode).
 */

export const THEME_STORAGE_KEY = 'tariqmap_theme';

/**
 * Resolves the initial theme preference from storage or fallback.
 *
 * @param {Storage|null} storage
 * @param {boolean} prefersDark
 * @returns {'dark'|'light'}
 */
export function getInitialTheme(storage, prefersDark = false) {
  try {
    const saved = storage?.getItem(THEME_STORAGE_KEY);
    if (saved === 'dark' || saved === 'light') return saved;
  } catch {}
  return prefersDark ? 'dark' : 'light';
}

/**
 * Resolves the inverted theme.
 *
 * @param {'dark'|'light'} current
 * @returns {'dark'|'light'}
 */
export function resolveNextTheme(current) {
  return current === 'dark' ? 'light' : 'dark';
}
