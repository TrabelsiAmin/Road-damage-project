import fs from 'fs';
import { describe, expect, it } from 'vitest';
import { renderToStaticMarkup } from 'react-dom/server';
import { TechnicalRecommendation } from './TechnicalRecommendation.jsx';

const QWEN_UNAVAILABLE = '8,4 Go de RAM libre ne suffisent pas pour les accueillir.';

const CANNED = [
  'Démonstration Colab',
  'Colab demonstration',
  'Ce n\'est pas un appel en direct',
  'This is not a live call',
  'data-colab-demonstration',
  'dégradations structurelles et les dégradations superficielles',
  'aspect humide et luisant',
  'couverture générale d\'une nouvelle couche',
  'défaut de portance du sol support',
  'dinars tunisiens n\'a pas été trouvée',
  '0.7111',
  '0.6881',
  '0.6133',
  '0.7412',
  '0.5284',
  'http://127.0.0.1:8000',
];

function visibleText(html) {
  return html
    .replace(/&#x27;|&#39;/g, "'")
    .replace(/&quot;/g, '"')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>');
}

describe('assistant chat panel', () => {
  it('renders a live transcript and none of the five recorded answers', () => {
    const html = renderToStaticMarkup(
      <TechnicalRecommendation lang="fr" selection={null} request={null} />,
    );
    const text = visibleText(html);
    for (const snippet of CANNED) {
      expect(text, snippet).not.toContain(snippet);
    }
    expect(text).toContain('Adresse de l\'API Colab');
    expect(html).toContain('data-assistant-panel="true"');
    expect(html).toContain('data-assistant-transcript="live"');
    expect(html).toContain('data-assistant-url="true"');
    expect(html).toContain('https://….ngrok-free.app');
    expect(html).not.toContain('data-colab-demonstration');
  });

  it('states that Qwen could not be loaded and does not send questions to the excerpt server', () => {
    const source = fs.readFileSync(new URL('./TechnicalRecommendation.jsx', import.meta.url), 'utf8');
    expect(source).toContain('Qwen2.5-7B-Instruct en 4 bits');
    expect(source).toContain(QWEN_UNAVAILABLE);
    expect(source).not.toContain('4721');
    expect(source).not.toContain('LOCAL_EXTRACT_BASE');
    expect(source).not.toContain('extraits des manuels');
    expect(source).not.toContain('sans le modèle Qwen');
  });
});
