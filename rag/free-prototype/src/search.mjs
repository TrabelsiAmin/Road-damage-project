/**
 * Same ranking as FAISS IndexFlatIP on L2-normalized vectors:
 * the score is the inner product, which equals cosine similarity.
 */

export function dot(left, right) {
  if (left.length !== right.length) {
    throw new Error(`dimension mismatch: ${left.length} vs ${right.length}`);
  }
  let sum = 0;
  for (let i = 0; i < left.length; i += 1) sum += left[i] * right[i];
  return sum;
}

export function l2norm(vector) {
  return Math.sqrt(dot(vector, vector));
}

export function isUnit(vector, tolerance = 1e-3) {
  return Math.abs(l2norm(vector) - 1) <= tolerance;
}

export function normalize(vector) {
  const norm = l2norm(vector);
  if (!Number.isFinite(norm) || norm === 0) {
    throw new Error('cannot normalize a zero vector');
  }
  return vector.map((value) => value / norm);
}

export function validateIndex(index) {
  if (!index || !Array.isArray(index.chunks) || index.chunks.length === 0) {
    throw new Error('index has no chunks');
  }
  const dimension = Number(index.dimension);
  if (!Number.isInteger(dimension) || dimension <= 0) {
    throw new Error('index dimension is missing');
  }
  const norms = [];
  for (const chunk of index.chunks) {
    if (!chunk || typeof chunk.source !== 'string' || typeof chunk.text !== 'string') {
      throw new Error('a chunk is missing source or text');
    }
    if (!Array.isArray(chunk.vector) || chunk.vector.length !== dimension) {
      throw new Error(`chunk vector is not ${dimension}-dimensional`);
    }
    norms.push(l2norm(chunk.vector));
  }
  return {
    chunks: index.chunks.length,
    dimension,
    maxAbsNormError: Math.max(...norms.map((norm) => Math.abs(norm - 1))),
    normalized: norms.every((norm) => Math.abs(norm - 1) <= 1e-3),
  };
}

export function search(index, query, k) {
  const info = validateIndex(index);
  if (!Array.isArray(query) || query.length !== info.dimension) {
    throw new Error(`query is not ${info.dimension}-dimensional`);
  }
  const limit = Math.min(Math.max(1, k), index.chunks.length);
  const scored = index.chunks.map((chunk, indexPos) => ({
    index: indexPos,
    source: chunk.source,
    text: chunk.text,
    score: dot(query, chunk.vector),
  }));
  scored.sort((left, right) => right.score - left.score || left.index - right.index);
  return scored.slice(0, limit);
}
