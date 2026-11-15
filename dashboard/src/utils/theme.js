/**
 * Persisted light/dark theme for the TariqMap dashboard.
 * A stored choice wins. Otherwise the system color scheme is used.
 */

export const THEME_STORAGE_KEY = 'tariqmap_theme';

/**
 * @param {Storage|null|undefined} storage
 * @param {boolean} [prefersDark]
 * @returns {'dark'|'light'}
 */
export function getInitialTheme(storage, prefersDark = false) {
  try {
    const stored = storage?.getItem?.(THEME_STORAGE_KEY);
    if (stored === 'dark' || stored === 'light') return stored;
  } catch {
    // Private mode or a blocked storage API falls through to the system preference.
  }
  return prefersDark ? 'dark' : 'light';
}

/**
 * @param {'dark'|'light'|string} current
 * @returns {'dark'|'light'}
 */
export function resolveNextTheme(current) {
  return current === 'dark' ? 'light' : 'dark';
}

/**
 * Paint a theme on the document. Storage is left untouched so a system
 * preference is not turned into a saved choice just by opening the page.
 * @param {'dark'|'light'|string} theme
 * @returns {'dark'|'light'}
 */
export function applyTheme(theme) {
  const next = theme === 'dark' ? 'dark' : 'light';
  if (typeof document !== 'undefined') {
    const root = document.documentElement;
    root.setAttribute('data-theme', next);
    root.classList.toggle('dark-mode', next === 'dark');
    root.style.colorScheme = next;
    if (document.body) {
      document.body.setAttribute('data-theme', next);
      document.body.classList.toggle('dark-mode', next === 'dark');
      document.body.style.colorScheme = next;
    }
  }
  return next;
}

/**
 * Remember an explicit light or dark choice.
 * @param {'dark'|'light'|string} theme
 * @param {Storage|null|undefined} [storage]
 * @returns {'dark'|'light'}
 */
export function persistTheme(theme, storage) {
  const next = theme === 'dark' ? 'dark' : 'light';
  const target = storage === undefined
    ? (typeof localStorage !== 'undefined' ? localStorage : null)
    : storage;
  try {
    target?.setItem?.(THEME_STORAGE_KEY, next);
  } catch (err) {
    console.warn('Failed to store theme:', err);
  }
  return next;
}
