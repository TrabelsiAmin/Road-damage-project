import fs from 'fs';
import { describe, it, expect } from 'vitest';
import {
  LOCAL_EXTRACT_BASE,
  RAG_DOWN_MESSAGE,
  RAG_TUNNEL_CLOSED_MESSAGE,
  RAG_URL_STORAGE_KEY,
  askRag,
  checkRagHealth,
  chooseAssistantBase,
  explainRagFailure,
  isPublicTunnel,
  buildMapRagPopupHtml,
  buildTechnicalQuestion,
  clampK,
  excerpt,
  isRagConfigured,
  normalizeRagBase,
  observationForRecommendation,
  parseRagResponse,
  questionHasForbiddenContent,
  ragAskUrl,
  ragHealthUrl,
  ragHttpErrorMessage,
  readStoredRagBase,
  writeStoredRagBase,
} from './ragClient.js';
import { ragDevProxy, ragProxyTarget } from '../../vite.ragProxy.js';

const BASE = 'https://demo.trycloudflare.com';

function memoryStorage(initial) {
  const data = new Map(initial ? Object.entries(initial) : []);
  return {
    getItem(key) { return data.has(key) ? data.get(key) : null; },
    setItem(key, value) { data.set(key, String(value)); },
    removeItem(key) { data.delete(key); },
  };
}

function liveFetch(onAsk) {
  return async (url, init) => {
    if (String(url).endsWith('/health')) {
      return { ok: true, status: 200, json: async () => ({ status: 'ok', vectors: 12 }) };
    }
    return onAsk(url, init);
  };
}

const LEAKY = {
  id: 'obs-1',
  anomaly_type: 'D40',
  status: 'confirmed',
  priority_label: 'HIGH',
  priority_score: 88,
  latitude: 36.806512,
  longitude: 10.181534,
  device_id: 'device-SECRET-99',
  notes: 'note personnelle de Ali Ben Salah',
  image_url: 'https://cdn.example.com/photo.jpg',
  storage_path: 'observation-images/secret.jpg',
  accuracy_meters: 4.2,
  detections: [{ class_code: 'D40', image_url: 'https://cdn.example.com/det.jpg' }],
};

describe('technical question', () => {
  it('builds a French question from the class, status, and priority already shown', () => {
    const question = buildTechnicalQuestion(LEAKY);
    expect(question).toContain('code RDD2022 D40');
    expect(question).not.toContain('Nid-de-poule');
    expect(question).toContain('priorité élevée');
    expect(question).toContain('Confirmé');
    expect(question).toContain('manuels de pathologie routière');
    expect(questionHasForbiddenContent(question)).toBe(false);
  });

  it('does not leak coordinates, photos, device ids, or free-text notes', () => {
    const question = buildTechnicalQuestion(LEAKY);
    const safe = observationForRecommendation(LEAKY);
    const serialized = `${question}\n${JSON.stringify(safe)}`;

    expect(Object.keys(safe).sort()).toEqual(['classCode', 'priority', 'status']);
    expect(safe).toEqual({ classCode: 'D40', priority: 'HIGH', status: 'confirmed' });
    expect(serialized).not.toContain('36.806512');
    expect(serialized).not.toContain('10.181534');
    expect(serialized).not.toContain('device-SECRET-99');
    expect(serialized).not.toContain('Ali Ben Salah');
    expect(serialized).not.toContain('https://');
    expect(serialized).not.toContain('photo.jpg');
    expect(serialized).not.toContain('secret.jpg');
    expect(serialized).not.toMatch(/latitude|longitude|device_id|image_url|storage_path|notes/i);
  });

  it('accepts a priority-list row and still drops its image and coordinates', () => {
    const row = {
      id: 'row-1',
      classCode: 'D00',
      priority: 'LOW',
      status: 'in_progress',
      latitude: 36.123456,
      longitude: 10.654321,
      imageUrl: 'https://example.com/thumb.jpg',
      score: 12,
    };
    const question = buildTechnicalQuestion(row);
    expect(question).toContain('code RDD2022 D00');
    expect(question).not.toContain('Fissure longitudinale');
    expect(question).toContain('priorité faible');
    expect(question).toContain('En cours');
    expect(question).not.toContain('36.123456');
    expect(question).not.toContain('10.654321');
    expect(question).not.toContain('thumb.jpg');
    expect(question).not.toContain(row.id);
  });

  it('uses the highest-priority cluster member and ignores the centroid', () => {
    const safe = observationForRecommendation({
      dominantClass: 'D20',
      status: 'confirmed',
      priorityLabel: 'LOW',
      latitude: 36.5,
      longitude: 9.4,
      members: [
        {
          anomaly_type: 'D00',
          status: 'unconfirmed',
          priority_label: 'LOW',
          priority_score: 10,
          latitude: 36.50001,
          longitude: 9.40001,
          device_id: 'phone-a',
        },
        {
          anomaly_type: 'D10',
          status: 'in_progress',
          priority_label: 'HIGH',
          priority_score: 91,
          latitude: 36.51111,
          longitude: 9.42222,
          device_id: 'phone-b',
          notes: 'commentaire citoyen',
        },
      ],
    });
    expect(safe).toEqual({ classCode: 'D10', priority: 'HIGH', status: 'in_progress' });
    expect(JSON.stringify(safe)).not.toContain('36.51111');
    expect(JSON.stringify(safe)).not.toContain('phone-b');
    expect(JSON.stringify(safe)).not.toContain('commentaire');
  });

  it('does not echo an unknown free-text class or status', () => {
    const question = buildTechnicalQuestion({
      anomaly_type: 'voir photo privée https://secret.example/a.jpg',
      status: 'appel du citoyen au 22123456',
      notes: 'Ali',
      latitude: 36.8,
      longitude: 10.1,
    });
    expect(question).toContain('n\'est pas renseignée');
    expect(question).not.toContain('secret.example');
    expect(question).not.toContain('22123456');
    expect(question).not.toContain('Ali');
    expect(question).not.toContain('36.8');
  });

  it('keeps the map popup to class, priority, and status', () => {
    const html = buildMapRagPopupHtml({
      classCode: 'D20',
      classLabel: 'Faïençage (Fatigue)',
      priorityLabel: 'HIGH',
      statusLabel: 'Confirmé',
      buttonLabel: 'Recommandation technique',
    });
    expect(html).toContain('data-rag-ask="true"');
    expect(html).toContain('Faïençage (Fatigue)');
    expect(html).toContain('Recommandation technique');
    expect(html).not.toMatch(/latitude|longitude|https?:|device_id/i);
    expect(buildMapRagPopupHtml({
      classLabel: '<img src=x onerror=alert(1)>',
      buttonLabel: '"onclick"',
    })).toContain('&lt;img');
  });
});

describe('RAG response parsing and errors', () => {
  it('parses answer and sources', () => {
    const parsed = parseRagResponse({
      answer: '  Le scellement convient aux fissures fines.  ',
      sources: [
        {
          source: 'data/Cours_Pathologies.txt',
          score: 0.8124,
          text: 'Le scellement des fissures limite les infiltrations. '.repeat(20),
        },
      ],
      latitude: 36.8,
    });
    expect(parsed.ok).toBe(true);
    expect(parsed.answer).toBe('Le scellement convient aux fissures fines.');
    expect(parsed.sources).toHaveLength(1);
    expect(parsed.sources[0].source).toBe('Cours_Pathologies.txt');
    expect(parsed.sources[0].score).toBeCloseTo(0.8124);
    expect(parsed.sources[0].excerpt.endsWith('…')).toBe(true);
    expect(parsed.sources[0].excerpt.length).toBeLessThanOrEqual(280);
    expect(excerpt('court')).toBe('court');
  });

  it('rejects malformed payloads', () => {
    expect(parseRagResponse(null).error.code).toBe('invalid_response');
    expect(parseRagResponse({ answer: 'ok' }).error.code).toBe('invalid_response');
    expect(parseRagResponse({ answer: '', sources: [] }).error.code).toBe('invalid_response');
    expect(parseRagResponse({
      answer: 'ok',
      sources: [{ source: 'a.txt', score: 'haute', text: 'x' }],
    }).error.code).toBe('invalid_response');
  });

  it('returns a structured error when the API URL is missing and does not call the network', async () => {
    let called = false;
    const result = await askRag({
      question: 'Qu\'est-ce qu\'une ornière ?',
      fetchImpl: () => {
        called = true;
      },
    });
    expect(called).toBe(false);
    expect(result.ok).toBe(false);
    expect(result.error.code).toBe('not_configured');
    expect(result.error.message).toBe(RAG_DOWN_MESSAGE);
    expect(result.error.message).not.toMatch(/127\.0\.0\.1/);
    expect(result.answer).toBeUndefined();
    expect(isRagConfigured({ VITE_RAG_API_URL: '' })).toBe(false);
    expect(isRagConfigured({ VITE_RAG_API_URL: 'https://session.ngrok-free.app' })).toBe(true);
  });

  it('posts question and k to {base}/ask without a recorded answer', async () => {
    const calls = [];
    const result = await askRag({
      question: '  Causes usuelles d\'un nid-de-poule ?  ',
      k: 5,
      base: `${BASE}/`,
      latitude: 36.8,
      longitude: 10.18,
      device_id: 'should-not-send',
      photo: 'https://cdn.example.com/a.jpg',
      fetchImpl: liveFetch(async (url, init) => {
        calls.push({ url, init });
        return {
          ok: true,
          json: async () => ({
            answer: 'Un nid-de-poule résulte d\'une désagrégation localisée.',
            sources: [{ source: 'Pathologie_des_routes.txt', score: 0.71, text: 'Désagrégation localisée de l\'enrobé.' }],
          }),
        };
      }),
    });

    expect(result.ok).toBe(true);
    expect(calls).toHaveLength(1);
    expect(calls[0].url).toBe(ragAskUrl(BASE));
    expect(calls[0].url).toBe(`${BASE}/ask`);
    expect(calls[0].init.method).toBe('POST');
    expect(calls[0].init.headers['ngrok-skip-browser-warning']).toBe('true');
    const body = JSON.parse(calls[0].init.body);
    expect(Object.keys(body).sort()).toEqual(['k', 'question']);
    expect(body.k).toBe(5);
    expect(body.question).toBe('Causes usuelles d\'un nid-de-poule ?');
    expect(calls[0].init.body).not.toMatch(/latitude|longitude|device_id|photo/i);
  });

  it('posts /ask and returns the HTTP error without inventing an answer', async () => {
    const calls = [];
    const question = 'Quel est le prix d\'une tonne d\'enrobé bitumineux ?';
    const result = await askRag({
      question,
      base: BASE,
      fetchImpl: async (url, init) => {
        calls.push({ url: String(url), method: init?.method, body: init?.body });
        return { ok: false, status: 503, json: async () => ({}) };
      },
    });
    expect(calls).toHaveLength(1);
    expect(calls[0].url).toBe(`${BASE}/ask`);
    expect(calls[0].method).toBe('POST');
    expect(JSON.parse(calls[0].body)).toEqual({ question, k: 5 });
    expect(result.ok).toBe(false);
    expect(result.error.code).toBe('http_error');
    expect(result.error.status).toBe(503);
    expect(result.error.message).toBe(ragHttpErrorMessage(503));
    expect(result.answer).toBeUndefined();
    expect(JSON.stringify(result)).not.toMatch(/scellement|réparation|fissure longitudinale/i);
  });

  it('blocks a question that itself carries a link or coordinates', async () => {
    let called = false;
    const fetchImpl = () => {
      called = true;
    };
    const linked = await askRag({
      question: 'Voir https://cdn.example.com/photo.jpg',
      base: BASE,
      fetchImpl,
    });
    const coords = await askRag({
      question: 'Dégradation au point 36.8065, 10.1815',
      base: BASE,
      fetchImpl,
    });
    expect(called).toBe(false);
    expect(linked.error.code).toBe('forbidden_payload');
    expect(coords.error.code).toBe('forbidden_payload');
  });

  it('maps timeout, network, and HTTP failures', async () => {
    const timeout = await askRag({
      question: 'Quelles sont les causes usuelles d\'une fissure ?',
      k: 99,
      base: BASE,
      timeoutMs: 20,
      fetchImpl: liveFetch((_url, init) => new Promise((_resolve, reject) => {
        init.signal.addEventListener('abort', () => {
          const err = new Error('aborted');
          err.name = 'AbortError';
          reject(err);
        });
      })),
    });
    expect(timeout.error.code).toBe('timeout');
    expect(timeout.error.message).toBe(RAG_TUNNEL_CLOSED_MESSAGE);

    const network = await askRag({
      question: 'Quelles sont les causes usuelles d\'une fissure ?',
      base: BASE,
      fetchImpl: liveFetch(() => {
        throw new TypeError('Failed to fetch');
      }),
    });
    expect(network.error.code).toBe('network');
    expect(network.error.message).toBe(RAG_TUNNEL_CLOSED_MESSAGE);

    const down = await askRag({
      question: 'Quelles sont les causes usuelles d\'une fissure ?',
      base: BASE,
      fetchImpl: liveFetch(async () => ({ ok: false, status: 502, json: async () => ({}) })),
    });
    expect(down.error.code).toBe('http_error');
    expect(down.error.status).toBe(502);
    expect(down.error.message).toBe('Erreur HTTP 502');

    const cancelled = new AbortController();
    cancelled.abort();
    const aborted = await askRag({
      question: 'Quelles sont les causes usuelles d\'une fissure ?',
      base: BASE,
      signal: cancelled.signal,
      fetchImpl: liveFetch((_url, init) => new Promise((_resolve, reject) => {
        init.signal.addEventListener('abort', () => {
          const err = new Error('aborted');
          err.name = 'AbortError';
          reject(err);
        });
      })),
    });
    expect(aborted.error.code).toBe('aborted');
  });

  it('clamps k to 1–8', () => {
    expect(clampK(undefined)).toBe(5);
    expect(clampK(0)).toBe(1);
    expect(clampK(3.2)).toBe(3);
    expect(clampK(8)).toBe(8);
    expect(clampK(40)).toBe(8);
  });
});

describe('RAG health', () => {
  it('stays unavailable without a public address and does not call the network', async () => {
    let called = false;
    const result = await checkRagHealth({
      fetchImpl: () => {
        called = true;
      },
    });
    expect(called).toBe(false);
    expect(result.ok).toBe(false);
    expect(result.error.code).toBe('not_configured');
    expect(result.error.message).toBe(RAG_DOWN_MESSAGE);
    expect(result.error.message).not.toMatch(/127\.0\.0\.1/);
    expect(result.answer).toBeUndefined();
  });

  it('accepts {base}/health and falls back to the tunnel root', async () => {
    const calls = [];
    const health = await checkRagHealth({
      base: `URL_DASHBOARD=${BASE}/ask`,
      fetchImpl: async (url) => {
        calls.push(url);
        return { ok: true, status: 200, json: async () => ({ status: 'ok', vectors: 12 }) };
      },
    });
    expect(health.ok).toBe(true);
    expect(calls).toEqual([ragHealthUrl(BASE)]);

    const fallbackCalls = [];
    const fallback = await checkRagHealth({
      base: BASE,
      fetchImpl: async (url) => {
        fallbackCalls.push(url);
        if (url === ragHealthUrl(BASE)) return { ok: false, status: 404, json: async () => ({}) };
        return { ok: true, status: 200, json: async () => ({ status: 'ok' }) };
      },
    });
    expect(fallback.ok).toBe(true);
    expect(fallbackCalls).toEqual([ragHealthUrl(BASE), `${BASE}/`]);
  });

  it('does not report the assistant ready when the probe fails', async () => {
    const down = await checkRagHealth({
      base: BASE,
      fetchImpl: async () => ({ ok: false, status: 503, json: async () => ({}) }),
    });
    expect(down.ok).toBe(false);
    expect(down.error.code).toBe('http_error');
    expect(down.error.message).toBe('Erreur HTTP 503');
    expect(down.error.message).not.toMatch(/127\.0\.0\.1|démonstration|Colab/);
    expect(down.answer).toBeUndefined();
  });
});

describe('closed Colab tunnel', () => {
  it('names the stopped session and does not invent an answer', () => {
    expect(isPublicTunnel('https://appraisal-handle-example.ngrok-free.dev')).toBe(true);
    expect(isPublicTunnel('https://session.trycloudflare.com')).toBe(true);
    expect(isPublicTunnel(LOCAL_EXTRACT_BASE)).toBe(false);
    expect(explainRagFailure(BASE, 'network')).toBe(RAG_TUNNEL_CLOSED_MESSAGE);
    expect(explainRagFailure(LOCAL_EXTRACT_BASE, 'network')).toBe(RAG_DOWN_MESSAGE);
    expect(RAG_TUNNEL_CLOSED_MESSAGE).not.toMatch(/dinars|nid-de-poule|fissure longitudinale/i);
  });

  it('keeps a live saved URL and uses local excerpts only after that URL fails', async () => {
    const savedCalls = [];
    const saved = await chooseAssistantBase({
      base: BASE,
      localBase: LOCAL_EXTRACT_BASE,
      fetchImpl: async (url) => {
        savedCalls.push(String(url));
        return { ok: true, status: 200, json: async () => ({ status: 'ok' }) };
      },
    });
    expect(saved).toEqual({ ok: true, base: BASE, via: 'saved' });
    expect(savedCalls).toEqual([`${BASE}/health`]);
    expect(savedCalls.some((url) => url.includes('127.0.0.1'))).toBe(false);

    const calls = [];
    const local = await chooseAssistantBase({
      base: 'https://session.ngrok-free.dev',
      localBase: LOCAL_EXTRACT_BASE,
      fetchImpl: async (url) => {
        calls.push(String(url));
        if (String(url).startsWith(LOCAL_EXTRACT_BASE)) {
          return { ok: true, status: 200, json: async () => ({ status: 'ok', mode: 'extract' }) };
        }
        throw new TypeError('Failed to fetch');
      },
    });
    expect(local.ok).toBe(true);
    expect(local.via).toBe('local');
    expect(local.base).toBe(LOCAL_EXTRACT_BASE);
    expect(local.savedDown).toBe(true);
    expect(calls[0]).toBe('https://session.ngrok-free.dev/health');

    const down = await chooseAssistantBase({
      base: 'https://session.ngrok-free.dev',
      localBase: LOCAL_EXTRACT_BASE,
      fetchImpl: async () => {
        throw new TypeError('Failed to fetch');
      },
    });
    expect(down.ok).toBe(false);
    expect(down.via).toBe('down');
    expect(down.error.message).toBe(RAG_TUNNEL_CLOSED_MESSAGE);
    expect(down.error.message).not.toMatch(/extrait|Longitudinal|D00/);
  });
});

describe('live chat only', () => {
  it('does not keep recorded answers or a localhost lecture in the client', () => {
    const source = fs.readFileSync(new URL('./ragClient.js', import.meta.url), 'utf8');
    expect(source).not.toContain('COLAB_DEMONSTRATION');
    expect(source).not.toContain('démonstration Colab');
    expect(source).not.toContain('Ce n\'est pas un appel en direct');
    expect(source).not.toContain('127.0.0.1:8000');
    expect(RAG_DOWN_MESSAGE).toBe('l\'API ne répond pas');
  });
});

describe('stored Colab address', () => {
  it('saves the public URL under tariqmap_rag_url and strips the printed prefix', () => {
    const store = memoryStorage({ [RAG_URL_STORAGE_KEY]: 'http://127.0.0.1:8000' });
    const saved = writeStoredRagBase('URL_DASHBOARD=https://abc.ngrok-free.app/ask', store);
    expect(saved).toBe('https://abc.ngrok-free.app');
    expect(store.getItem(RAG_URL_STORAGE_KEY)).toBe('https://abc.ngrok-free.app');
    expect(readStoredRagBase(store)).toBe('https://abc.ngrok-free.app');
    expect(readStoredRagBase(store)).not.toBe('http://127.0.0.1:8000');
    expect(normalizeRagBase('https://abc.ngrok-free.app/health')).toBe('https://abc.ngrok-free.app');
    expect(normalizeRagBase('pas une url')).toBe('');
    expect(writeStoredRagBase('', store)).toBe('');
    expect(store.getItem(RAG_URL_STORAGE_KEY)).toBeNull();
  });
});

describe('RAG dev proxy', () => {
  it('forwards /rag to the configured origin and injects the ngrok header', () => {
    expect(ragProxyTarget('')).toBeNull();
    expect(ragProxyTarget('not a url')).toBeNull();
    expect(ragDevProxy('')).toBeUndefined();

    const target = ragProxyTarget('https://session.ngrok-free.app/ask');
    expect(target).toBe('https://session.ngrok-free.app');

    const proxy = ragDevProxy('https://session.ngrok-free.app/ask');
    expect(proxy['/rag'].target).toBe('https://session.ngrok-free.app');
    expect(proxy['/rag'].changeOrigin).toBe(true);
    expect(proxy['/rag'].rewrite('/rag/ask')).toBe('/ask');
    expect(proxy['/rag'].rewrite('/rag')).toBe('/');

    const headers = {};
    const fake = {
      on(event, handler) {
        expect(event).toBe('proxyReq');
        handler({ setHeader: (name, value) => { headers[name] = value; } });
      },
    };
    proxy['/rag'].configure(fake);
    expect(headers['ngrok-skip-browser-warning']).toBe('true');
  });
});
