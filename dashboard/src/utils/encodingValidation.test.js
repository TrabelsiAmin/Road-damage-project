import { describe, it, expect } from 'vitest';
import fs from 'fs';
import path from 'path';

describe('Source Code UTF-8 Encoding Verification', () => {
  const BAD_PATTERNS = [
    /\u00c3\u00a9/, // corrupted é
    /\u00c3\u00a8/, // corrupted è
    /\u00c3\u00a0/, // corrupted à
    /\u00c3\u00a7/, // corrupted ç
    /\u00c3\u00aa/, // corrupted ê
    /\u00c3\u00b4/, // corrupted ô
    /\u00c3\u2030/, // corrupted É
    /\u00c2\u00ab/, // corrupted «
    /\u00c2\u00bb/, // corrupted »
    /\u00e2\u201d\u20ac/, // corrupted ─
    /\u00e2\u2020\u2019/, // corrupted →
    /\u00e2\u20ac\u00a2/, // corrupted •
    /\u00e2\u20ac\u201c/, // corrupted –
    /\u00e2\u20ac\u201d/, // corrupted —
  ];

  it('ensures App.jsx has zero UTF-8 mojibake patterns', () => {
    const appPath = path.resolve(__dirname, '../App.jsx');
    const content = fs.readFileSync(appPath, 'utf-8');

    for (const pattern of BAD_PATTERNS) {
      expect(pattern.test(content)).toBe(false);
    }
  });

  it('verifies expected proper French strings in App.jsx', () => {
    const appPath = path.resolve(__dirname, '../App.jsx');
    const content = fs.readFileSync(appPath, 'utf-8');

    expect(content).toContain('Métriques IA & Limites');
    expect(content).toContain('Priorité');
    expect(content).toContain('Détails cluster');
    expect(content).toContain('rejeté');
    expect(content).toContain('Signalements rejetés');
    expect(content).toContain('LÉGENDE');
    expect(content).toContain('Photo réservée autorité');
    expect(content).toContain('Échec du chargement');
    expect(content).toContain('Aperçu public flouté');
    expect(content).toContain('Connexion Autorité Municipale');
    expect(content).toContain('« sans anomalie »');
  });

  it('verifies expected proper French strings in constants.js', () => {
    const constPath = path.resolve(__dirname, '../constants.js');
    const content = fs.readFileSync(constPath, 'utf-8');

    for (const pattern of BAD_PATTERNS) {
      expect(pattern.test(content)).toBe(false);
    }
    expect(content).toContain('Non confirmé');
    expect(content).toContain('Indisponible');
    expect(content).not.toContain('Nid-de-poule');
    expect(content).not.toContain('Fissure longitudinale');
  });
});
