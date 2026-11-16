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

/** Address saved in the browser. The chat posts here and nowhere else. */
export const RAG_URL_STORAGE_KEY = 'tariqmap_rag_url';

/** Shown when the live API cannot be reached. Not a substitute answer. */
export const RAG_DOWN_MESSAGE = "l'API ne répond pas";

/** Dead ngrok / Cloudflare / localtunnel address. Not a substitute answer. */
export const RAG_TUNNEL_CLOSED_MESSAGE =
  "La session Colab est arrêtée : le tunnel est fermé.";

/**
 * Extractive manuals on this machine. The chat does not call this address:
 * that process does not run Qwen.
 */
export const LOCAL_EXTRACT_BASE = 'http://127.0.0.1:4721';

/**
 * Small Qwen Instruct on this CPU. Used only when neither the saved address
 * nor the configured Colab address answers /health. A live Colab URL still wins.
 */
export const LOCAL_QWEN_BASE = 'http://127.0.0.1:4733';

export function isPublicTunnel(base) {
  const root = normalizeRagBase(base);
  if (!root) return false;
  let host = '';
  try {
    host = new URL(root).hostname.toLowerCase();
  } catch {
    return false;
  }
  return (
    host.endsWith('.ngrok-free.app')
    || host.endsWith('.ngrok-free.dev')
    || host.endsWith('.ngrok.app')
    || host.endsWith('.ngrok.io')
    || host.endsWith('.trycloudflare.com')
    || host.endsWith('.loca.lt')
  );
}

export function explainRagFailure(base, kind) {
  if (
    isPublicTunnel(base)
    && (kind === 'network' || kind === 'timeout' || kind === 'unavailable')
  ) {
    return RAG_TUNNEL_CLOSED_MESSAGE;
  }
  return RAG_DOWN_MESSAGE;
}

export function ragHttpErrorMessage(status) {
  return `Erreur HTTP ${Number(status) || 0}`;
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

/** Colab address from the dashboard env. Empty when none is configured. */
export function configuredRagBase(env = import.meta.env) {
  return normalizeRagBase(env?.VITE_RAG_API_URL ?? '');
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
    return errorResult('not_configured', RAG_DOWN_MESSAGE);
  }
  const health = await probe(ragHealthUrl(root), fetchImpl, timeoutMs);
  if (health.ok) return { ok: true, payload: health.payload };
  if (health.status === 404) {
    const rootProbe = await probe(`${root}/`, fetchImpl, timeoutMs);
    if (rootProbe.ok) return { ok: true, payload: rootProbe.payload };
  }
  if (health.status) {
    return errorResult('http_error', ragHttpErrorMessage(health.status), { status: health.status });
  }
  if (health.code === 'timeout') {
    return errorResult('timeout', explainRagFailure(root, 'timeout'));
  }
  return errorResult('unavailable', explainRagFailure(root, 'unavailable'));
}

export async function askRag({
  question,
  k = RAG_K_DEFAULT,
  fetchImpl = globalThis.fetch,
  base = '',
  timeoutMs = RAG_TIMEOUT_MS,
  signal,
  checkHealth = false,
} = {}) {
  const root = normalizeRagBase(base);
  if (!root) {
    return errorResult('not_configured', RAG_DOWN_MESSAGE);
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
      if (!status) return errorResult('http_error', RAG_DOWN_MESSAGE, { status: 0 });
      return errorResult('http_error', ragHttpErrorMessage(status), { status });
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
      return errorResult('timeout', explainRagFailure(root, 'timeout'));
    }
    return errorResult('network', explainRagFailure(root, 'network'));
  } finally {
    clearTimeout(timer);
    signal?.removeEventListener('abort', onExternalAbort);
  }
}

/**
 * A saved address that answers /health wins, including one pasted later.
 * If it is missing or does not answer, the configured Colab address is
 * tried. localBase is used only after both of those fail. Storage is not
 * changed here, so a dead saved URL stays stored but does not block.
 */
export async function chooseAssistantBase({
  base = '',
  configuredBase = '',
  localBase = '',
  fetchImpl = globalThis.fetch,
  timeoutMs = RAG_HEALTH_TIMEOUT_MS,
} = {}) {
  const root = normalizeRagBase(base);
  if (root) {
    const health = await checkRagHealth({ base: root, fetchImpl, timeoutMs });
    if (health.ok) return { ok: true, base: root, via: 'saved', payload: health.payload };
  }
  const configured = normalizeRagBase(configuredBase);
  if (configured && configured !== root) {
    const configuredHealth = await checkRagHealth({ base: configured, fetchImpl, timeoutMs });
    if (configuredHealth.ok) {
      return {
        ok: true,
        base: configured,
        via: 'configured',
        savedDown: Boolean(root),
        payload: configuredHealth.payload,
      };
    }
  }
  const local = normalizeRagBase(localBase);
  if (local && local !== root && local !== configured) {
    const localHealth = await checkRagHealth({ base: local, fetchImpl, timeoutMs });
    if (localHealth.ok) {
      return {
        ok: true,
        base: local,
        via: 'local',
        savedDown: Boolean(root || configured),
        payload: localHealth.payload,
      };
    }
  }
  const failed = root || configured;
  return {
    ok: false,
    base: failed,
    via: 'down',
    error: {
      code: failed ? 'unavailable' : 'not_configured',
      message: failed ? explainRagFailure(failed, 'unavailable') : RAG_DOWN_MESSAGE,
    },
  };
}
