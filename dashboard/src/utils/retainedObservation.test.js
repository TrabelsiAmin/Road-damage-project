import { describe, expect, it } from 'vitest';
import { COLAB_DEMONSTRATION } from './ragClient.js';
import {
  LOCAL_RAG_BASE,
  recommendationForRetained,
  retainedObservationFrom,
} from './retainedObservation.js';

const SFAX = { latitude: 34.7406, longitude: 10.7603 };
const TUNIS = { latitude: 36.8065, longitude: 10.1815 };

describe('retained observation fields', () => {
  it('keeps the stored class code, derived place, date, and status', () => {
    const view = retainedObservationFrom({
      id: 'obs-1',
      anomaly_type: 'D40',
      status: 'confirmed',
      priority_label: 'HIGH',
      priority_score: 88,
      created_at: '2026-03-15T12:00:00Z',
      ...SFAX,
      device_id: 'secret-device',
      image_url: 'https://cdn.example.com/photo.jpg',
      notes: 'note privée',
    });
    expect(view).toEqual({
      classCode: 'D40',
      priority: 'HIGH',
      status: 'confirmed',
      place: 'Sfax Ville, Sfax',
      dateLabel: '15 mars 2026',
    });
    expect(JSON.stringify(view)).not.toMatch(/34\.7406|10\.7603|secret-device|photo\.jpg|note privée/);
  });

  it('uses the highest-priority member and does not invent a class name', () => {
    const view = retainedObservationFrom({
      dominantClass: 'D00',
      latitude: TUNIS.latitude,
      longitude: TUNIS.longitude,
      members: [
        {
          anomaly_type: 'D00',
          status: 'unconfirmed',
          priority_label: 'LOW',
          priority_score: 10,
          ...TUNIS,
          created_at: '2026-01-02T10:00:00Z',
        },
        {
          anomaly_type: 'D10',
          status: 'in_progress',
          priority_label: 'HIGH',
          priority_score: 91,
          ...SFAX,
          created_at: '2026-03-15T12:00:00Z',
          notes: 'commentaire',
        },
      ],
    });
    expect(view.classCode).toBe('D10');
    expect(view.status).toBe('in_progress');
    expect(view.place).toBe('Sfax Ville, Sfax');
    expect(view.dateLabel).toBe('15 mars 2026');
    expect(view.place).not.toContain('Tunis');
    expect(JSON.stringify(view)).not.toMatch(/Nid-de-poule|Faïençage|commentaire/);
  });

  it('does not treat a public cell priority colour as a stored priority', () => {
    const view = retainedObservationFrom({
      publicCell: true,
      dominantClass: 'D20',
      priorityLabel: 'MEDIUM',
      latitude: TUNIS.latitude,
      longitude: TUNIS.longitude,
      count: 4,
    });
    expect(view).toEqual({
      classCode: 'D20',
      priority: null,
      status: null,
      place: 'Tunis Ville, Tunis',
      dateLabel: null,
    });
  });

  it('drops an unknown free-text class', () => {
    const view = retainedObservationFrom({
      anomaly_type: 'nid de poule privé',
      status: 'appel au 22123456',
      latitude: 36.8,
      longitude: 10.1,
    });
    expect(view.classCode).toBeNull();
    expect(view.status).toBeNull();
    expect(JSON.stringify(view)).not.toMatch(/nid de poule|22123456/);
  });
});

describe('recommendation for a retained observation', () => {
  const observation = {
    classCode: 'D40',
    priority: 'HIGH',
    status: 'confirmed',
    place: 'Sfax Ville, Sfax',
    dateLabel: '15 mars 2026',
  };

  it('returns the live answer and does not replace it with a recorded one', async () => {
    const calls = [];
    const result = await recommendationForRetained({
      observation,
      storedBase: 'https://session.trycloudflare.com',
      fetchImpl: async (url, init) => {
        calls.push(String(url));
        if (String(url).endsWith('/health')) {
          return { ok: true, status: 200, json: async () => ({ status: 'ok' }) };
        }
        const body = JSON.parse(init.body);
        expect(body.question).toContain('code RDD2022 D40');
        expect(body.question).not.toContain('Sfax');
        expect(body.question).not.toContain('Nid-de-poule');
        expect(Object.keys(body).sort()).toEqual(['k', 'question']);
        return {
          ok: true,
          json: async () => ({
            answer: 'Le manuel décrit un principe de réparation pour ce code.',
            sources: [{ source: 'Cours_Pathologies.txt', score: 0.42, text: 'Extrait du manuel.' }],
          }),
        };
      },
    });
    expect(result.live).toBe(true);
    expect(result.recorded).toBe(false);
    expect(result.answer).toMatch(/manuel/);
    expect(result.sources[0].source).toBe('Cours_Pathologies.txt');
    expect(result.sources[0].score).toBeCloseTo(0.42);
    expect(calls[0]).toBe('https://session.trycloudflare.com/health');
    expect(calls.some((url) => url.startsWith(LOCAL_RAG_BASE))).toBe(false);
  });

  it('tries this machine after the saved address fails, then refuses to invent a repair', async () => {
    const calls = [];
    const result = await recommendationForRetained({
      observation,
      storedBase: 'https://down.example',
      fetchImpl: async (url) => {
        calls.push(String(url));
        throw new TypeError('Failed to fetch');
      },
    });
    expect(calls.some((url) => url.startsWith('https://down.example'))).toBe(true);
    expect(calls.some((url) => url.startsWith(LOCAL_RAG_BASE))).toBe(true);
    expect(result.live).toBe(false);
    expect(result.recorded).toBe(false);
    expect(result.answer).toBeUndefined();
    expect(result.error.code).toBe('colab_required');
    expect(result.question).toContain('code RDD2022 D40');
    expect(result.question).not.toContain('Sfax');
  });

  it('returns a recorded Colab answer only for one of the five questions', async () => {
    const item = COLAB_DEMONSTRATION[0];
    const calls = [];
    const result = await recommendationForRetained({
      question: item.question,
      storedBase: '',
      fetchImpl: async (url) => {
        calls.push(String(url));
        throw new TypeError('Failed to fetch');
      },
    });
    expect(calls[0]).toBe(`${LOCAL_RAG_BASE}/health`);
    expect(result.live).toBe(false);
    expect(result.recorded).toBe(true);
    expect(result.answer).toBe(item.answer);
    expect(result.sources[0].source).toBe(item.source);
    expect(result.sources[0].score).toBeCloseTo(item.score);
  });
});
