/**
 * TariqMap is light mode only. Stored or system dark preferences are ignored.
 */

export const THEME_STORAGE_KEY = 'tariqmap_theme';

/**
 * @param {Storage|null} [_storage]
 * @param {boolean} [_prefersDark]
 * @returns {'light'}
 */
export function getInitialTheme(_storage, _prefersDark = false) {
  return 'light';
}

/**
 * @param {'dark'|'light'} [_current]
 * @returns {'light'}
 */
export function resolveNextTheme(_current) {
  return 'light';
}
