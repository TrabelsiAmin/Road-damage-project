import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { embedQuestion, generateAnswer, readEmbeddingVector } from '../src/providers.mjs';
import { isUnit, l2norm, normalize, search } from '../src/search.mjs';
import { handleRequest } from '../src/worker.mjs';

const questions = JSON.parse(readFileSync(new URL('../fixtures/questions.json', import.meta.url), 'utf8'));

function unitVector(dimension, index) {
  const vector = Array.from({ length: dimension }, () => 0);
  vector[index] = 1;
  return vector;
}

function plantedIndex() {
  const planted = questions.filter((item) => item.plantedSource);
  const chunks = planted.map((item, position) => ({
    source: item.plantedSource,
    text: `Extrait de test pour ${item.id}.`,
    vector: unitVector(16, position),
  }));
  return { dimension: 16, chunks };
}

function env() {
  return {
    CLOUDFLARE_ACCOUNT_ID: 'account-test',
    CLOUDFLARE_API_TOKEN: 'cf-token-test',
    GROQ_API_KEY: 'groq-token-test',
  };
}

function embeddingResponse(vector, status = 200) {
  return new Response(JSON.stringify({ result: { data: [vector], shape: [1, vector.length] } }), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function groqResponse(answer, status = 200) {
  return new Response(JSON.stringify({
    choices: [{ message: { content: answer } }],
  }), { status, headers: { 'Content-Type': 'application/json' } });
}

test('index vectors are unit length and the nearest chunk wins', () => {
  const index = plantedIndex();
  for (const chunk of index.chunks) assert.equal(isUnit(chunk.vector), true);
  questions.filter((item) => item.plantedSource).forEach((item, position) => {
    const found = search(index, unitVector(16, position), 3);
    assert.equal(found[0].source, item.plantedSource);
    assert.ok(Math.abs(found[0].score - 1) < 1e-9);
    assert.ok(found[1].score < 1e-9);
  });
});

test('a non-unit query is reported and normalized before scoring', () => {
  const raw = [2, 0, 0];
  assert.equal(isUnit(raw), false);
  const query = normalize(raw);
  assert.ok(Math.abs(l2norm(query) - 1) < 1e-9);
  const index = {
    dimension: 3,
    chunks: [
      { source: 'a.txt', text: 'a', vector: [1, 0, 0] },
      { source: 'b.txt', text: 'b', vector: [0, 1, 0] },
    ],
  };
  assert.equal(search(index, query, 1)[0].source, 'a.txt');
});

test('search of 479 vectors of dimension 1024 stays under 100 ms', () => {
  const dimension = 1024;
  const count = 479;
  const chunks = Array.from({ length: count }, (_, position) => {
    const vector = Array.from({ length: dimension }, () => 0);
    vector[position % dimension] = 1;
    return { source: `doc-${position}.txt`, text: `chunk ${position}`, vector };
  });
  const query = chunks[10].vector;
  const started = performance.now();
  const found = search({ dimension, chunks }, query, 5);
  const elapsed = performance.now() - started;
  assert.equal(found[0].source, 'doc-10.txt');
  assert.ok(elapsed < 100, `search took ${elapsed} ms`);
  console.log(`SEARCH_479x1024_MS ${elapsed.toFixed(3)}`);
});

test('health does not call a provider', async () => {
  let calls = 0;
  const response = await handleRequest(new Request('http://prototype.local/health'), env(), {
    index: plantedIndex(),
    fetchImpl: () => {
      calls += 1;
      throw new Error('provider called');
    },
  });
  const body = await response.json();
  assert.equal(response.status, 200);
  assert.equal(body.ok, true);
  assert.equal(body.index.dimension, 16);
  assert.equal(body.index.normalized, true);
  assert.equal(body.generator, 'qwen/qwen3.8-27b');
  assert.equal(calls, 0);
});

test('ask returns the planted source and keeps the key out of the response', async () => {
  const index = plantedIndex();
  const item = questions[0];
  const calls = [];
  const response = await handleRequest(new Request('http://prototype.local/ask', {
    method: 'POST',
    body: JSON.stringify({ question: item.question, k: 3 }),
  }), env(), {
    index,
    fetchImpl: async (url, init) => {
      calls.push({ url, init });
      if (String(url).includes('cloudflare.com')) return embeddingResponse(unitVector(16, 0));
      return groqResponse('Une fissure longitudinale est décrite dans le manuel.');
    },
  });
  const body = await response.json();
  assert.equal(response.status, 200);
  assert.equal(body.sources[0].source, item.plantedSource);
  assert.equal(body.generator, 'qwen/qwen3.8-27b');
  assert.equal(body.fallback, false);
  assert.equal(body.embedding.dimension, 16);
  assert.equal(body.embedding.queryNormalized, false);
  const serialized = JSON.stringify(body);
  assert.equal(serialized.includes('groq-token-test'), false);
  assert.equal(serialized.includes('cf-token-test'), false);
  const groqCall = calls.find((call) => String(call.url).includes('groq.com'));
  const prompt = JSON.parse(groqCall.init.body).messages[1].content;
  assert.equal(prompt.includes(item.plantedSource), true);
  assert.equal(prompt.includes('prix'), false);
});

test('representative questions retrieve only their planted source', async () => {
  const index = plantedIndex();
  const planted = questions.filter((item) => item.plantedSource);
  for (let position = 0; position < planted.length; position += 1) {
    const response = await handleRequest(new Request('http://prototype.local/ask', {
      method: 'POST',
      body: JSON.stringify({ question: planted[position].question, k: 1 }),
    }), env(), {
      index,
      fetchImpl: async (url) => {
        if (String(url).includes('cloudflare.com')) return embeddingResponse(unitVector(16, position));
        return groqResponse('Réponse limitée aux extraits.');
      },
    });
    const body = await response.json();
    assert.ok(Array.isArray(body.sources));
    assert.equal(body.sources.length, 1);
    assert.equal(body.sources[0].source, planted[position].plantedSource);
    assert.equal(body.sources[0].text.includes(planted[position].id), true);
  }
});

test('a missing fact does not invent a source file', async () => {
  const index = plantedIndex();
  const response = await handleRequest(new Request('http://prototype.local/ask', {
    method: 'POST',
    body: JSON.stringify({ question: questions.at(-1).question, k: 2 }),
  }), env(), {
    index,
    fetchImpl: async (url) => {
      if (String(url).includes('cloudflare.com')) {
        return embeddingResponse(normalize(Array.from({ length: 16 }, () => 0.01)));
      }
      return groqResponse('Les extraits ne contiennent pas cette information.');
    },
  });
  const body = await response.json();
  assert.equal(response.status, 200);
  assert.equal(body.answer.includes('ne contiennent pas'), true);
  for (const source of body.sources) {
    assert.equal(source.text.includes('prix'), false);
  }
});

test('embedding quota stops before Groq is called', async () => {
  const calls = [];
  const response = await handleRequest(new Request('http://prototype.local/ask', {
    method: 'POST',
    body: JSON.stringify({ question: 'Qu\'est-ce qu\'une ornière ?', k: 2 }),
  }), env(), {
    index: plantedIndex(),
    fetchImpl: async (url) => {
      calls.push(String(url));
      return new Response('{}', { status: 429 });
    },
  });
  const body = await response.json();
  assert.equal(response.status, 503);
  assert.equal(body.error, 'quota');
  assert.equal(body.provider, 'cloudflare');
  assert.equal(calls.length, 1);
  assert.equal(calls[0].includes('cloudflare.com'), true);
});

test('Groq 429 falls back once, then reports quota', async () => {
  const models = [];
  const response = await handleRequest(new Request('http://prototype.local/ask', {
    method: 'POST',
    body: JSON.stringify({ question: 'Qu\'est-ce qu\'une ornière ?', k: 2 }),
  }), env(), {
    index: plantedIndex(),
    fetchImpl: async (url, init) => {
      if (String(url).includes('cloudflare.com')) return embeddingResponse(unitVector(16, 4));
      models.push(JSON.parse(init.body).model);
      if (models.length === 1) return new Response('{}', { status: 429 });
      return groqResponse('Secours documentaire.');
    },
  });
  const body = await response.json();
  assert.equal(response.status, 200);
  assert.deepEqual(models, ['qwen/qwen3.8-27b', 'llama-3.1-8b-instant']);
  assert.equal(body.fallback, true);
  assert.equal(body.generator, 'llama-3.1-8b-instant');

  const exhausted = [];
  const blocked = await handleRequest(new Request('http://prototype.local/ask', {
    method: 'POST',
    body: JSON.stringify({ question: 'Qu\'est-ce qu\'une ornière ?', k: 2 }),
  }), env(), {
    index: plantedIndex(),
    fetchImpl: async (url, init) => {
      if (String(url).includes('cloudflare.com')) return embeddingResponse(unitVector(16, 4));
      exhausted.push(JSON.parse(init.body).model);
      return new Response('{}', { status: 429 });
    },
  });
  const blockedBody = await blocked.json();
  assert.equal(blocked.status, 503);
  assert.equal(blockedBody.error, 'quota');
  assert.equal(blockedBody.fallbackTried, true);
  assert.equal(exhausted.length, 2);
});

test('a vector of the wrong length is rejected', async () => {
  const response = await handleRequest(new Request('http://prototype.local/ask', {
    method: 'POST',
    body: JSON.stringify({ question: 'Qu\'est-ce qu\'une ornière ?', k: 2 }),
  }), env(), {
    index: plantedIndex(),
    fetchImpl: async () => embeddingResponse([1, 0]),
  });
  const body = await response.json();
  assert.equal(response.status, 422);
  assert.equal(body.error, 'dimension_mismatch');
  assert.equal(body.expected, 16);
  assert.equal(body.received, 2);
});

test('provider request shapes match the free APIs', async () => {
  const embedded = await embedQuestion({
    question: 'faïençage',
    env: env(),
    fetchImpl: async (url, init) => {
      assert.equal(url, 'https://api.cloudflare.com/client/v4/accounts/account-test/ai/run/@cf/baai/bge-m3');
      assert.equal(init.headers.Authorization, 'Bearer cf-token-test');
      assert.deepEqual(JSON.parse(init.body), { text: ['faïençage'] });
      return embeddingResponse(unitVector(4, 0));
    },
  });
  assert.equal(embedded.vector.length, 4);
  assert.deepEqual(readEmbeddingVector({ data: [0.2, 0.3] }), [0.2, 0.3]);

  const generated = await generateAnswer({
    prompt: 'contexte',
    env: env(),
    model: 'qwen/qwen3.8-27b',
    fetchImpl: async (url, init) => {
      assert.equal(url, 'https://api.groq.com/openai/v1/chat/completions');
      assert.equal(init.headers.Authorization, 'Bearer groq-token-test');
      const body = JSON.parse(init.body);
      assert.equal(body.model, 'qwen/qwen3.8-27b');
      assert.equal(body.temperature, 0);
      assert.equal(body.max_tokens, 300);
      return groqResponse('ok');
    },
  });
  assert.equal(generated.answer, 'ok');
});
