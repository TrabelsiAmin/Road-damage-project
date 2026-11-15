/**
 * Fields shown on the retained-observation card.
 * The question sent to the manuals keeps only class, priority, and status.
 * Place is derived from a stored point. Nothing here invents a row.
 */

import { DAMAGE_CLASSES } from '../constants';
import {
  askRag,
  buildTechnicalQuestion,
  findColabDemonstration,
  normalizeRagBase,
  observationForRecommendation,
} from './ragClient';
import { formatIncidentDate } from './overviewPresentation';
import { resolveTunisiaAdmin } from './tunisiaGeo';

export const LOCAL_RAG_BASE = 'http://127.0.0.1:8000';

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
 * Live call against the saved Colab address, then this machine.
 * A recorded Colab answer is used only when the question is one of the five.
 * Anything else stays unanswered. No repair procedure is written here.
 */
export async function recommendationForRetained({
  observation,
  lang = 'fr',
  question,
  storedBase = '',
  localBase = LOCAL_RAG_BASE,
  k,
  fetchImpl,
  signal,
} = {}) {
  const asked = String(question || '').trim() || buildTechnicalQuestion(observation, lang);
  const bases = [];
  const stored = normalizeRagBase(storedBase);
  const local = normalizeRagBase(localBase);
  if (stored) bases.push(stored);
  if (local && local !== stored) bases.push(local);

  for (const base of bases) {
    if (signal?.aborted) {
      return { ok: false, live: false, recorded: false, question: asked, error: { code: 'aborted' } };
    }
    const response = await askRag({ question: asked, k, base, fetchImpl, signal });
    if (response.error?.code === 'aborted') {
      return { ok: false, live: false, recorded: false, question: asked, error: response.error };
    }
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
  }

  const recorded = findColabDemonstration(asked);
  if (recorded) {
    return {
      ok: true,
      live: false,
      recorded: true,
      question: asked,
      answer: recorded.answer,
      sources: [{ source: recorded.source, score: recorded.score, text: '', excerpt: '' }],
    };
  }

  return {
    ok: false,
    live: false,
    recorded: false,
    question: asked,
    error: { code: 'colab_required' },
  };
}
