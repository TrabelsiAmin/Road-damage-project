import { DAMAGE_CLASSES, STATUS_LABELS } from '../constants';
import { observationClass, observationPriority } from './ministryAnalytics';

export const RAG_ASK_PATH = '/rag/ask';
export const RAG_HEALTH_PATH = '/rag/health';
export const RAG_ROOT_PATH = '/rag/';
export const RAG_TIMEOUT_MS = 120000;
export const RAG_HEALTH_TIMEOUT_MS = 8000;
export const RAG_K_MIN = 1;
export const RAG_K_MAX = 8;
export const RAG_K_DEFAULT = 5;

/** Optional API base saved in the browser. Not a public tunnel. */
export const RAG_URL_STORAGE_KEY = 'tariqmap_rag_url';

/**
 * Shown when this dashboard cannot reach the RAG API.
 * The model answers in the Colab notebook on that machine. This computer
 * cannot call 127.0.0.1:8000 there. This note is not a live response.
 */
export const RAG_CONNECT_NOTE = {
  fr: 'Le modèle répond dans le notebook Colab, sur la machine Colab. Ce tableau de bord est sur un autre ordinateur et ne peut pas appeler 127.0.0.1:8000 là-bas.',
  en: 'The model answers in the Colab notebook, on the Colab machine. This dashboard is on another computer and cannot call 127.0.0.1:8000 there.',
};

export function shouldShowColabDemonstration({ backend } = {}) {
  return backend === 'down';
}

/** Recorded Colab run. Shown only while this dashboard cannot reach the API. */
export const COLAB_DEMONSTRATION = [
  {
    question: 'Quels sont les principaux types de dégradations des chaussées ?',
    answer: 'Les principaux types de dégradations des chaussées se classent en deux grandes familles : les dégradations structurelles et les dégradations superficielles. Les dégradations structurelles apparaissent au sein de la structure de chaussée ou de son support et remettent en cause le patrimoine. Les dégradations superficielles naissent dans la couche de surface de la chaussée et affectent d\'abord ses qualités superficielles.',
    source: 'Cours_Pathologies_et_entretien_des_routes_et_ouvrages_dart_4geniecivil (2).txt',
    score: 0.7111,
    refusal: false,
  },
  {
    question: 'Comment identifier une dégradation de la chaussée à partir de son aspect visuel ?',
    answer: 'Une dégradation de la chaussée peut être identifiée à partir de son aspect visuel en distinguant plusieurs niveaux de sévérité : Faible (premiers indices intermittents, difficile à percevoir à vitesse moyenne, confort de roulement non altéré) ; Moyen (dégradation continue, symptômes plus visibles, confort légèrement altéré) ; Majeur (aspect humide et luisant sur la majorité de la surface, texture du revêtement invisible, bruit similaire à celui sur un revêtement mouillé).',
    source: 'MTQ_Manuel_identification_degradations_chaussees_flexibles_PROJET (2).txt',
    score: 0.6881,
    refusal: false,
  },
  {
    question: 'Quels principes de réparation s\'appliquent à une fissure de chaussée ?',
    answer: 'Les principes de réparation d\'une fissure de chaussée dépendent du type de chaussée et de la cause de la fissure. Pour les chaussées souples, la réparation peut impliquer le couverture générale d\'une nouvelle couche de revêtement pour résorber les fissures existantes et prévenir de nouvelles. Pour les chaussées en matériaux traités, la réparation peut nécessiter le traitement des couches affectées et la réparation des joints de raccordement. Dans certains cas, comme la présence de tranchées sous-jacentes, des travaux spécifiques peuvent être nécessaires pour corriger la cause sous-jacente avant de procéder à la réparation.',
    source: 'Cours_Pathologies_et_entretien_des_routes_et_ouvrages_dart_4geniecivil (2).txt',
    score: 0.6133,
    refusal: false,
  },
  {
    question: 'Quelles sont les principales causes des fissures de chaussée ?',
    answer: 'Les principales causes des fissures de chaussée incluent le défaut de portance du sol support dans les chaussées souples ; des défauts de la structure dans les chaussées bitumineuses, comme la rupture par fatigue ; un défaut de collage de la couche de roulement sur la couche d\'enrobé sous-jacente ; la fatigue du revêtement due à des flexions alternées et des efforts de tension causés par les variations de température ; l\'eau ; le trafic lourd et répété ; la mauvaise qualité des matériaux et un compactage insuffisant ; le climat ; le drainage défectueux ; des fissures transversales liées aux assises traitées aux liants hydrauliques.',
    source: 'Cours_Pathologies_et_entretien_des_routes_et_ouvrages_dart_4geniecivil (2).txt',
    score: 0.7412,
    refusal: false,
  },
  {
    question: 'Quel est le prix d\'une tonne d\'enrobé bitumineux en dinars tunisiens ?',
    answer: 'L\'information sur le prix d\'une tonne d\'enrobé bitumineux en dinars tunisiens n\'a pas été trouvée dans le contexte fourni.',
    source: 'Benjelloun_Cours_Routes_EPA_Agadir_Chapitres_1-2 (2).txt',
    score: 0.5284,
    refusal: true,
  },
];

export function findColabDemonstration(question) {
  const key = String(question || '').replace(/\s+/g, ' ').trim().toLocaleLowerCase('fr');
  if (!key) return null;
  return COLAB_DEMONSTRATION.find((item) => (
    item.question.replace(/\s+/g, ' ').trim().toLocaleLowerCase('fr') === key
  )) || null;
}

export function normalizeRagBase(value) {
  let raw = String(value ?? '').trim();
  if (!raw) return '';
  const labeled = raw.match(/URL_DASHBOARD\s*=\s*(\S+)/i);
  if (labeled) raw = labeled[1];
  raw = raw.replace(/[),.;]+$/g, '');
  let url;
  try {
    url = new URL(raw);
  } catch {
    return '';
  }
  if (url.protocol !== 'http:' && url.protocol !== 'https:') return '';
  let path = url.pathname.replace(/\/+$/, '');
  path = path.replace(/\/(?:ask|health)$/i, '');
  if (path === '/') path = '';
  return `${url.origin}${path}`;
}

function storageOr(storage) {
  if (storage) return storage;
  try {
    return globalThis.localStorage;
  } catch {
    return null;
  }
}

export function readStoredRagBase(storage) {
  const store = storageOr(storage);
  if (!store) return '';
  try {
    return normalizeRagBase(store.getItem(RAG_URL_STORAGE_KEY) || '');
  } catch {
    return '';
  }
}

export function writeStoredRagBase(value, storage) {
  const store = storageOr(storage);
  const base = normalizeRagBase(value);
  if (!store) return base;
  try {
    if (base) store.setItem(RAG_URL_STORAGE_KEY, base);
    else store.removeItem(RAG_URL_STORAGE_KEY);
  } catch {
    // Private mode or a full quota still leaves the normalized value in memory.
  }
  return base;
}

export function ragHealthUrl(base) {
  const root = normalizeRagBase(base);
  return root ? `${root}/health` : '';
}

export function ragAskUrl(base) {
  const root = normalizeRagBase(base);
  return root ? `${root}/ask` : '';
}

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
    ? `code RDD2022 ${known.code}`
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

async function probe(path, fetchImpl, timeoutMs) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetchImpl(path, {
      method: 'GET',
      headers: {
        Accept: 'application/json',
        'ngrok-skip-browser-warning': 'true',
      },
      signal: controller.signal,
    });
    if (!response?.ok) return { ok: false, status: Number(response?.status) || 0 };
    const payload = await response.json();
    if (payload && payload.status === 'ok') return { ok: true, payload };
    return { ok: false, status: Number(response.status) || 0, code: 'not_ready' };
  } catch (err) {
    if (err?.name === 'AbortError') return { ok: false, code: 'timeout' };
    return { ok: false, code: 'network' };
  } finally {
    clearTimeout(timer);
  }
}

export async function checkRagHealth({
  fetchImpl = globalThis.fetch,
  base = '',
  timeoutMs = RAG_HEALTH_TIMEOUT_MS,
} = {}) {
  const root = normalizeRagBase(base);
  if (!root) {
    return errorResult('not_configured', RAG_CONNECT_NOTE.fr);
  }
  const health = await probe(ragHealthUrl(root), fetchImpl, timeoutMs);
  if (health.ok) return { ok: true, payload: health.payload };
  if (health.status === 404) {
    const rootProbe = await probe(`${root}/`, fetchImpl, timeoutMs);
    if (rootProbe.ok) return { ok: true, payload: rootProbe.payload };
  }
  if (health.code === 'timeout') {
    return errorResult('timeout', RAG_CONNECT_NOTE.fr);
  }
  return errorResult('unavailable', RAG_CONNECT_NOTE.fr);
}

export async function askRag({
  question,
  k = RAG_K_DEFAULT,
  fetchImpl = globalThis.fetch,
  base = '',
  timeoutMs = RAG_TIMEOUT_MS,
  signal,
  checkHealth = true,
} = {}) {
  const root = normalizeRagBase(base);
  if (!root) {
    return errorResult('not_configured', RAG_CONNECT_NOTE.fr);
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

  if (checkHealth) {
    const health = await checkRagHealth({
      fetchImpl,
      base: root,
      timeoutMs: Math.min(timeoutMs, RAG_HEALTH_TIMEOUT_MS),
    });
    if (!health.ok) return health;
  }

  const passages = clampK(k);
  const controller = new AbortController();
  const onExternalAbort = () => controller.abort();
  if (signal) signal.addEventListener('abort', onExternalAbort);
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetchImpl(ragAskUrl(root), {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
        'ngrok-skip-browser-warning': 'true',
        'Bypass-Tunnel-Reminder': 'true',
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
          ? `L'assistant ne répond pas (HTTP ${status}). ${RAG_CONNECT_NOTE.fr}`
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
      return errorResult('timeout', RAG_CONNECT_NOTE.fr);
    }
    return errorResult('network', RAG_CONNECT_NOTE.fr);
  } finally {
    clearTimeout(timer);
    signal?.removeEventListener('abort', onExternalAbort);
  }
}
