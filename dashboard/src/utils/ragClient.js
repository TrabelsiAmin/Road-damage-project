import { DAMAGE_CLASSES, STATUS_LABELS } from '../constants';
import { observationClass, observationPriority } from './ministryAnalytics';

export const RAG_ASK_PATH = '/rag/ask';
export const RAG_TIMEOUT_MS = 90000;
export const RAG_K_MIN = 1;
export const RAG_K_MAX = 8;
export const RAG_K_DEFAULT = 5;

const PRIORITY_FR = {
  HIGH: 'élevée',
  MEDIUM: 'moyenne',
  LOW: 'faible',
};

const PRIORITY_EN = {
  HIGH: 'high',
  MEDIUM: 'medium',
  LOW: 'low',
};

const FORBIDDEN_QUESTION = [
  /https?:\/\//i,
  /\bdata:image\//i,
  /\b(latitude|longitude|device_id|image_url|photo_url|storage_path)\b/i,
  /-?\d{1,3}\.\d{4,}\s*[,;]\s*-?\d{1,3}\.\d{4,}/,
];

export function isRagConfigured(env = import.meta.env) {
  const value = String(env?.VITE_RAG_API_URL ?? '').trim();
  return /^https?:\/\//i.test(value);
}

export function clampK(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return RAG_K_DEFAULT;
  return Math.min(RAG_K_MAX, Math.max(RAG_K_MIN, Math.round(parsed)));
}

function knownClassCode(observation) {
  const code = observation?.classCode || observationClass(observation);
  return code && DAMAGE_CLASSES[code] ? code : null;
}

function knownPriority(observation) {
  const label = observation?.priority || observationPriority(observation);
  if (label === 'HIGH' || label === 'MEDIUM' || label === 'LOW') return label;
  return null;
}

function knownStatus(observation) {
  const status = observation?.status;
  return status && STATUS_LABELS[status] ? status : null;
}

function pickHighestPriorityMember(cluster) {
  const members = Array.isArray(cluster?.members) ? cluster.members.filter(Boolean) : [];
  if (members.length === 0) {
    return {
      classCode: cluster?.dominantClass,
      status: cluster?.status,
      priority: cluster?.priorityLabel,
      priority_score: cluster?.maxPriorityScore,
    };
  }
  return members.reduce((best, item) => {
    const score = Number(item?.priority_score);
    const bestScore = Number(best?.priority_score);
    if (!Number.isFinite(bestScore)) return item;
    if (!Number.isFinite(score)) return best;
    return score > bestScore ? item : best;
  });
}

/**
 * Class, workflow status, and priority only.
 * Coordinates, media, device ids, and free-text notes are dropped.
 */
export function observationForRecommendation(source) {
  const isCluster = Array.isArray(source?.members)
    || (source != null && Object.prototype.hasOwnProperty.call(source, 'dominantClass'));
  const observation = isCluster ? pickHighestPriorityMember(source) : source;
  return {
    classCode: knownClassCode(observation),
    priority: knownPriority(observation),
    status: knownStatus(observation),
  };
}

export function buildTechnicalQuestion(observation, lang = 'fr') {
  const safe = observationForRecommendation(observation);
  const french = lang !== 'en';
  const known = safe.classCode ? DAMAGE_CLASSES[safe.classCode] : null;
  const classText = known
    ? `${french ? known.fr : known.en} (classe RDD2022 ${known.code})`
    : (french
      ? 'dégradation routière dont la classe RDD2022 n\'est pas renseignée'
      : 'road damage whose RDD2022 class is not recorded');
  const qualifiers = [];
  if (safe.priority) {
    qualifiers.push(french
      ? `de priorité ${PRIORITY_FR[safe.priority]}`
      : `at ${PRIORITY_EN[safe.priority]} priority`);
  }
  if (safe.status) {
    const statusLabel = french ? STATUS_LABELS[safe.status].fr : STATUS_LABELS[safe.status].en;
    qualifiers.push(french ? `au statut « ${statusLabel} »` : `with status "${statusLabel}"`);
  }
  const qualifier = qualifiers.length ? `, ${qualifiers.join(', ')}` : '';
  if (french) {
    return `Quelle recommandation technique d'entretien s'applique à un désordre de type ${classText}${qualifier} ? Décrivez les caractéristiques, les causes usuelles et les principes de réparation, uniquement à partir des manuels de pathologie routière.`;
  }
  return `What maintenance recommendation applies to ${classText}${qualifier}? Describe the characteristics, usual causes, and repair principles using only the road-pathology manuals.`;
}

export function questionHasForbiddenContent(question) {
  const text = String(question || '');
  return FORBIDDEN_QUESTION.some((pattern) => pattern.test(text));
}

export function sourceFileName(source) {
  const name = String(source || '').split(/[/\\]/).filter(Boolean).pop();
  return name || 'source';
}

export function excerpt(text, max = 280) {
  const clean = String(text || '').replace(/\s+/g, ' ').trim();
  if (clean.length <= max) return clean;
  return `${clean.slice(0, max - 1).trimEnd()}…`;
}

export function escapeHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

export function buildMapRagPopupHtml({
  classCode = '—',
  classLabel = '',
  priorityLabel = '—',
  statusLabel = '—',
  buttonLabel = 'Recommandation technique',
} = {}) {
  return `
    <div class="rag-map-popup">
      <strong>${escapeHtml(classCode)} · ${escapeHtml(classLabel)}</strong>
      <p>${escapeHtml(priorityLabel)} · ${escapeHtml(statusLabel)}</p>
      <button type="button" data-rag-ask="true">${escapeHtml(buttonLabel)}</button>
    </div>
  `;
}

function errorResult(code, message, extra = {}) {
  return { ok: false, error: { code, message, ...extra } };
}

export function parseRagResponse(payload) {
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
    return errorResult('invalid_response', 'La réponse reçue n\'a pas le format attendu.');
  }
  if (typeof payload.answer !== 'string' || !payload.answer.trim()) {
    return errorResult('invalid_response', 'La réponse reçue ne contient pas de texte.');
  }
  if (!Array.isArray(payload.sources)) {
    return errorResult('invalid_response', 'La réponse reçue ne contient pas de liste de sources.');
  }

  const sources = [];
  for (const item of payload.sources) {
    if (!item || typeof item !== 'object' || Array.isArray(item)) {
      return errorResult('invalid_response', 'Une source reçue est illisible.');
    }
    if (typeof item.source !== 'string' || !item.source.trim()) {
      return errorResult('invalid_response', 'Une source reçue n\'a pas de nom de fichier.');
    }
    if (typeof item.text !== 'string') {
      return errorResult('invalid_response', 'Une source reçue n\'a pas d\'extrait.');
    }
    const score = Number(item.score);
    if (!Number.isFinite(score)) {
      return errorResult('invalid_response', 'Une source reçue n\'a pas de score numérique.');
    }
    sources.push({
      source: sourceFileName(item.source),
      score,
      text: item.text,
      excerpt: excerpt(item.text),
    });
  }

  return {
    ok: true,
    answer: payload.answer.trim(),
    sources,
  };
}

export async function askRag({
  question,
  k = RAG_K_DEFAULT,
  fetchImpl = globalThis.fetch,
  configured = isRagConfigured(),
  timeoutMs = RAG_TIMEOUT_MS,
  path = RAG_ASK_PATH,
  signal,
} = {}) {
  if (!configured) {
    return errorResult(
      'not_configured',
      'L\'assistant documentaire est indisponible : VITE_RAG_API_URL n\'est pas renseignée. Le notebook Colab n\'est pas lancé depuis ce tableau de bord.',
    );
  }

  const trimmed = String(question ?? '').trim();
  if (!trimmed) {
    return errorResult('empty_question', 'Saisissez une question technique.');
  }
  if (questionHasForbiddenContent(trimmed)) {
    return errorResult(
      'forbidden_payload',
      'Cette question contient un lien, des coordonnées ou un identifiant. L\'assistant n\'accepte qu\'une question technique sur la pathologie routière.',
    );
  }

  if (signal?.aborted) {
    return errorResult('aborted', 'Question annulée.');
  }

  const passages = clampK(k);
  const controller = new AbortController();
  const onExternalAbort = () => controller.abort();
  if (signal) signal.addEventListener('abort', onExternalAbort);
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetchImpl(path, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
        'ngrok-skip-browser-warning': 'true',
      },
      body: JSON.stringify({ question: trimmed, k: passages }),
      signal: controller.signal,
    });

    if (!response?.ok) {
      const status = Number(response?.status) || 0;
      const unreachable = status === 404 || status === 0 || status >= 500;
      return errorResult(
        'http_error',
        unreachable
          ? `L'API documentaire est injoignable (HTTP ${status}). Le notebook Colab est peut-être arrêté, ou l'adresse ngrok a changé.`
          : `L'API documentaire a renvoyé une erreur HTTP ${status}.`,
        { status },
      );
    }

    let payload;
    try {
      payload = await response.json();
    } catch {
      return errorResult('invalid_response', 'La réponse reçue n\'est pas un JSON exploitable.');
    }
    return parseRagResponse(payload);
  } catch (err) {
    if (err?.name === 'AbortError') {
      if (signal?.aborted) return errorResult('aborted', 'Question annulée.');
      return errorResult(
        'timeout',
        'Le service n\'a pas répondu à temps. Le notebook Colab est peut-être arrêté, ou l\'adresse ngrok a changé.',
      );
    }
    return errorResult(
      'network',
      'Impossible de joindre l\'API. Vérifiez que la session Colab tourne encore : l\'adresse publique change à chaque redémarrage.',
    );
  } finally {
    clearTimeout(timer);
    signal?.removeEventListener('abort', onExternalAbort);
  }
}
