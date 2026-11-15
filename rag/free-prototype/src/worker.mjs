import {
  FALLBACK_MODEL,
  PRIMARY_MODEL,
  buildPrompt,
  embedQuestion,
  generateAnswer,
} from './providers.mjs';
import { isUnit, normalize, search, validateIndex } from './search.mjs';

export function json(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
  });
}

function clampK(value) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1 || parsed > 8) return null;
  return parsed;
}

function healthBody(index, env) {
  const info = validateIndex(index);
  return {
    ok: info.normalized,
    index: info,
    embedding: '@cf/baai/bge-m3',
    generator: env?.GROQ_API_KEY ? PRIMARY_MODEL : 'missing',
    fallback: FALLBACK_MODEL,
  };
}

export async function handleRequest(request, env, { fetchImpl = fetch, index } = {}) {
  const url = new URL(request.url);
  if (request.method === 'GET' && url.pathname === '/health') {
    if (!index) return json(503, { ok: false, error: 'index_missing' });
    try {
      const body = healthBody(index, env);
      return json(body.ok ? 200 : 503, body);
    } catch (error) {
      return json(503, { ok: false, error: 'index_invalid', detail: error.message });
    }
  }

  if (!(request.method === 'POST' && url.pathname === '/ask')) {
    return json(404, { error: 'not_found' });
  }
  if (!index) return json(503, { error: 'index_missing' });

  let payload;
  try {
    payload = await request.json();
  } catch {
    return json(400, { error: 'invalid_json' });
  }
  const question = typeof payload?.question === 'string' ? payload.question.trim() : '';
  const k = clampK(payload?.k ?? 5);
  if (!question) return json(400, { error: 'empty_question' });
  if (k == null) return json(400, { error: 'invalid_k' });
  if (!env?.CLOUDFLARE_ACCOUNT_ID || !env?.CLOUDFLARE_API_TOKEN || !env?.GROQ_API_KEY) {
    return json(503, { error: 'not_configured' });
  }

  const started = Date.now();
  const embedded = await embedQuestion({ question, env, fetchImpl });
  const embedMs = Date.now() - started;
  if (embedded.status === 429) {
    return json(503, { error: 'quota', provider: 'cloudflare', stage: 'embedding' });
  }
  if (embedded.status !== 200 || !embedded.vector) {
    return json(503, { error: 'upstream', provider: 'cloudflare', status: embedded.status });
  }

  let info;
  try {
    info = validateIndex(index);
  } catch (error) {
    return json(503, { error: 'index_invalid', detail: error.message });
  }
  if (embedded.vector.length !== info.dimension) {
    return json(422, {
      error: 'dimension_mismatch',
      expected: info.dimension,
      received: embedded.vector.length,
    });
  }

  const rawNorm = Math.sqrt(embedded.vector.reduce((sum, value) => sum + value * value, 0));
  const queryWasUnit = isUnit(embedded.vector);
  const query = queryWasUnit ? embedded.vector : normalize(embedded.vector);
  const searchStarted = Date.now();
  const passages = search(index, query, k);
  const searchMs = Date.now() - searchStarted;

  const prompt = buildPrompt(question, passages);
  const generateStarted = Date.now();
  let generated = await generateAnswer({
    prompt,
    env,
    fetchImpl,
    model: PRIMARY_MODEL,
  });
  let model = PRIMARY_MODEL;
  let usedFallback = false;
  if (generated.status === 429) {
    usedFallback = true;
    generated = await generateAnswer({
      prompt,
      env,
      fetchImpl,
      model: FALLBACK_MODEL,
    });
    model = FALLBACK_MODEL;
  }
  const generateMs = Date.now() - generateStarted;
  if (generated.status === 429) {
    return json(503, { error: 'quota', provider: 'groq', fallbackTried: true });
  }
  if (generated.status !== 200 || !generated.answer) {
    return json(503, { error: 'upstream', provider: 'groq', status: generated.status });
  }

  return json(200, {
    answer: generated.answer,
    sources: passages.map((passage) => ({
      source: passage.source,
      score: passage.score,
      text: passage.text,
    })),
    generator: model,
    fallback: usedFallback,
    embedding: {
      model: '@cf/baai/bge-m3',
      dimension: embedded.vector.length,
      rawNorm,
      queryNormalized: !queryWasUnit,
    },
    timings: { embedMs, searchMs, generateMs },
  });
}
