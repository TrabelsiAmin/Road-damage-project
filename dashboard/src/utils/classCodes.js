/** Stored class ids the Android app already uses. Do not rename these. */
export const KNOWN_CLASS_CODES = ['D00', 'D10', 'D20', 'D40'];

export const UNKNOWN_CLASS_LABEL = 'Unknown class';

export function rawClassCode(value) {
  if (value == null) return null;
  const text = String(value).trim();
  return text.length ? text : null;
}

/**
 * First stored class on an observation. Null when nothing was stored.
 * Does not substitute D40.
 */
export function observationClassCode(obs) {
  if (!obs) return null;
  return rawClassCode(
    obs.anomaly_type ||
      obs.dominant_class ||
      obs.dominantClass ||
      obs.detections?.[0]?.class_code ||
      obs.detections?.[0]?.classCode,
  );
}

export function isKnownClassCode(value) {
  const code = rawClassCode(value);
  return code != null && KNOWN_CLASS_CODES.includes(code);
}

/** UI text. Known codes stay D00–D40. Missing and unrecognized codes do not get a new name. */
export function displayClassCode(value) {
  const code = rawClassCode(value);
  if (!isKnownClassCode(code)) return UNKNOWN_CLASS_LABEL;
  return code;
}

/** Null when the value must be left out of a D00/D10/D20/D40 statistic. */
export function statClassCode(value) {
  return isKnownClassCode(value) ? rawClassCode(value) : null;
}
