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
 * Apply the theme to the document and remember it.
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
    }
  }
  try {
    if (typeof localStorage !== 'undefined') {
      localStorage.setItem(THEME_STORAGE_KEY, next);
    }
  } catch {
    // The visual theme still applies when storage is unavailable.
  }
  return next;
}
