/**
 * Optional live probe. It does nothing unless the three variables are set in
 * the environment, and it never writes them to disk.
 */
import { embedQuestion, generateAnswer } from '../src/providers.mjs';

const env = {
  CLOUDFLARE_ACCOUNT_ID: process.env.CLOUDFLARE_ACCOUNT_ID || '',
  CLOUDFLARE_API_TOKEN: process.env.CLOUDFLARE_API_TOKEN || '',
  GROQ_API_KEY: process.env.GROQ_API_KEY || '',
};

if (!env.CLOUDFLARE_ACCOUNT_ID || !env.CLOUDFLARE_API_TOKEN || !env.GROQ_API_KEY) {
  console.log(JSON.stringify({
    live: 'skipped',
    reason: 'CLOUDFLARE_ACCOUNT_ID, CLOUDFLARE_API_TOKEN, or GROQ_API_KEY is absent',
  }));
  process.exit(0);
}

const question = "Qu'est-ce qu'une fissure longitudinale ?";
const embedded = await embedQuestion({ question, env, fetchImpl: fetch });
const generated = embedded.status === 200
  ? await generateAnswer({
    prompt: question,
    env,
    fetchImpl: fetch,
    model: 'qwen/qwen3.8-27b',
  })
  : null;

console.log(JSON.stringify({
  live: 'called',
  embeddingStatus: embedded.status,
  embeddingDimension: embedded.vector?.length ?? null,
  groqStatus: generated?.status ?? null,
  groqAnswerChars: generated?.answer?.length ?? 0,
}));
