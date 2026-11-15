import { readFileSync, writeFileSync } from 'node:fs';
import { search } from '../src/search.mjs';

const [exportPath, outPath, kArg] = process.argv.slice(2);
const k = Number(kArg || 5);
const index = JSON.parse(readFileSync(exportPath, 'utf8'));
const ranks = index.chunks.map((chunk) => {
  const hits = search(index, chunk.vector, k).map((hit) => ({
    id: hit.index,
    score: hit.score,
  }));
  return { id: chunk.id, hits };
});
writeFileSync(outPath, JSON.stringify(ranks));
console.log(JSON.stringify({ queries: ranks.length, k }));
