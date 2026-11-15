/**
 * Fields shown on the retained-observation card.
 * The question sent to the manuals keeps only class, priority, and status.
 * Place is derived from a stored point. Nothing here invents a row.
 */

import { DAMAGE_CLASSES } from '../constants';
import {
  askRag,
  buildTechnicalQuestion,
  normalizeRagBase,
  observationForRecommendation,
  RAG_DOWN_MESSAGE,
} from './ragClient';
import { formatIncidentDate } from './overviewPresentation';
import { resolveTunisiaAdmin } from './tunisiaGeo';

function finitePoint(latitude, longitude) {
  const lat = Number(latitude);
  const lng = Number(longitude);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  if (Math.abs(lat) > 90 || Math.abs(lng) > 180) return null;
  if (lat === 0 && lng === 0) return null;
  return { latitude: lat, longitude: lng };
}

function placeFromPoint(point) {
  if (!point) return null;
  const geo = resolveTunisiaAdmin(point.latitude, point.longitude);
  if (!geo?.governorate || geo.governorate === 'Non déterminé') return null;
  if (geo.municipality && geo.municipality !== geo.governorate) {
    return `${geo.municipality}, ${geo.governorate}`;
  }
  return geo.governorate;
}

function highestPriorityMember(members) {
  return members.reduce((best, item) => {
    const score = Number(item?.priority_score);
    const bestScore = Number(best?.priority_score);
    if (!Number.isFinite(bestScore)) return item;
    if (!Number.isFinite(score)) return best;
    return score > bestScore ? item : best;
  });
}

function knownCode(value) {
  return value && DAMAGE_CLASSES[value] ? value : null;
}

/**
 * @returns {{classCode: string|null, priority: string|null, status: string|null, place: string|null, dateLabel: string|null}|null}
 */
export function retainedObservationFrom(source, lang = 'fr') {
  if (!source || typeof source !== 'object') return null;

  if (source.publicCell) {
    const code = knownCode(source.dominantClass || source.dominant_class);
    const place = placeFromPoint(finitePoint(
      source.latitude ?? source.cell_lat,
      source.longitude ?? source.cell_lng,
    ));
    if (!code && !place) return null;
    return {
      classCode: code,
      priority: null,
      status: null,
      place,
      dateLabel: null,
    };
  }

  const safe = observationForRecommendation(source);
  const isCluster = Array.isArray(source.members)
    || Object.prototype.hasOwnProperty.call(source, 'dominantClass');
  let located = source;
  let dated = source;
  if (isCluster && Array.isArray(source.members) && source.members.length > 0) {
    located = highestPriorityMember(source.members.filter(Boolean));
    dated = located;
  }
  const point = finitePoint(located?.latitude, located?.longitude)
    || finitePoint(source.latitude, source.longitude);
  const dateLabel = formatIncidentDate(
    dated?.created_at || dated?.captured_at || dated?.createdAt || source.newestDate || source.created_at,
    lang,
  );
  const place = placeFromPoint(point);
  if (!safe.classCode && !safe.priority && !safe.status && !place && !dateLabel) return null;
  return {
    classCode: safe.classCode,
    priority: safe.priority,
    status: safe.status,
    place,
    dateLabel,
  };
}

/**
 * One live call to the saved Colab address.
 * No localhost fallback and no recorded answer.
 */
export async function recommendationForRetained({
  observation,
  lang = 'fr',
  question,
  storedBase = '',
  k = 5,
  fetchImpl,
  signal,
} = {}) {
  const asked = String(question || '').trim() || buildTechnicalQuestion(observation, lang);
  const stored = normalizeRagBase(storedBase);
  if (!stored) {
    return {
      ok: false,
      live: false,
      recorded: false,
      question: asked,
      error: { code: 'not_configured', message: RAG_DOWN_MESSAGE },
    };
  }
  if (signal?.aborted) {
    return { ok: false, live: false, recorded: false, question: asked, error: { code: 'aborted' } };
  }
  const response = await askRag({
    question: asked,
    k,
    base: stored,
    fetchImpl,
    signal,
    checkHealth: false,
  });
  if (response.ok) {
    return {
      ok: true,
      live: true,
      recorded: false,
      question: asked,
      answer: response.answer,
      sources: response.sources,
    };
  }
  return {
    ok: false,
    live: false,
    recorded: false,
    question: asked,
    error: response.error?.message
      ? response.error
      : { code: 'unavailable', message: RAG_DOWN_MESSAGE },
  };
}
