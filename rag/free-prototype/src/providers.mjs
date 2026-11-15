export const EMBEDDING_MODEL = '@cf/baai/bge-m3';
export const PRIMARY_MODEL = 'qwen/qwen3.8-27b';
export const FALLBACK_MODEL = 'llama-3.1-8b-instant';
export const EXPECTED_DIMENSION = 1024;

export function embeddingUrl(accountId) {
  return `https://api.cloudflare.com/client/v4/accounts/${accountId}/ai/run/${EMBEDDING_MODEL}`;
}

export function readEmbeddingVector(payload) {
  const data = payload?.result?.data ?? payload?.data;
  if (!Array.isArray(data)) return null;
  if (Array.isArray(data[0])) return data[0];
  if (typeof data[0] === 'number') return data;
  return null;
}

export function buildPrompt(question, passages) {
  const blocks = passages.map((passage, position) => (
    `[${position + 1}] ${passage.source}\n${passage.text}`
  ));
  return [
    'Réponds en français, uniquement à partir des extraits.',
    'Si les extraits ne contiennent pas la réponse, dis-le explicitement.',
    'Ne cite un nom de fichier que s\'il apparaît dans les extraits.',
    '',
    blocks.join('\n\n'),
    '',
    `Question : ${question}`,
  ].join('\n');
}

async function readJson(response) {
  try {
    return await response.json();
  } catch {
    return null;
  }
}

export async function embedQuestion({ question, env, fetchImpl }) {
  const response = await fetchImpl(embeddingUrl(env.CLOUDFLARE_ACCOUNT_ID), {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${env.CLOUDFLARE_API_TOKEN}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ text: [question] }),
  });
  const payload = await readJson(response);
  return { status: response.status, vector: readEmbeddingVector(payload) };
}

export async function generateAnswer({ prompt, env, fetchImpl, model }) {
  const response = await fetchImpl('https://api.groq.com/openai/v1/chat/completions', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${env.GROQ_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model,
      temperature: 0,
      max_tokens: 300,
      messages: [
        { role: 'system', content: 'Tu es un assistant documentaire de pathologie routière.' },
        { role: 'user', content: prompt },
      ],
    }),
  });
  const payload = await readJson(response);
  const answer = payload?.choices?.[0]?.message?.content;
  return {
    status: response.status,
    answer: typeof answer === 'string' ? answer.trim() : '',
  };
}
