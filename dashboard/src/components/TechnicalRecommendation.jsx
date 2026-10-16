import React, { useEffect, useRef, useState } from 'react';
import { BookOpen } from 'lucide-react';
import { DAMAGE_CLASSES, STATUS_LABELS } from '../constants';
import {
  RAG_K_DEFAULT,
  RAG_K_MAX,
  RAG_K_MIN,
  askRag,
  buildTechnicalQuestion,
  isRagConfigured,
  sourceFileName,
} from '../utils/ragClient';

const COPY = {
  fr: {
    title: 'Recommandation technique',
    intro: 'L\'assistant répond à partir des manuels de pathologie routière. Il ne lit pas les observations en direct et ne reçoit ni photo, ni coordonnée, ni identifiant d\'appareil.',
    unavailable: 'L\'assistant est indisponible : aucune adresse d\'API n\'est configurée (VITE_RAG_API_URL). Le notebook Colab n\'est pas lancé depuis ce tableau de bord.',
    selected: 'Observation retenue',
    none: 'Choisissez une observation dans la file prioritaire ou dans l\'infobulle d\'un agrégat sur la carte.',
    askSelection: 'Demander une recommandation',
    questionLabel: 'Question technique',
    placeholder: 'Posez une question technique. L\'assistant répond à partir des manuels de pathologie routière, pas à partir des observations en direct.',
    passages: 'Passages',
    passagesHelp: 'Nombre d\'extraits de manuels transmis au modèle.',
    submit: 'Interroger les manuels',
    loading: 'Recherche dans les manuels et rédaction de la réponse… Cela peut prendre une minute.',
    empty: 'Aucune réponse à afficher. Les manuels ne sont interrogés qu\'à votre demande.',
    sent: 'Question envoyée',
    answer: 'Réponse',
    sources: 'Sources',
    noSources: 'Aucun passage n\'a été renvoyé avec cette réponse.',
    score: 'Score',
    disclaimer: 'Réponse rédigée par un modèle à partir des manuels. Vérifiez les sources avant toute décision technique.',
    unclassified: 'Non classé',
    unknownPriority: 'Priorité non renseignée',
    unknownStatus: 'Statut non renseigné',
  },
  en: {
    title: 'Technical recommendation',
    intro: 'The assistant answers from road-pathology manuals. It does not read live observations and is not sent photos, coordinates, or device identifiers.',
    unavailable: 'The assistant is unavailable: no API address is configured (VITE_RAG_API_URL). The Colab notebook is not running from this dashboard.',
    selected: 'Selected observation',
    none: 'Choose an observation in the priority list or in a map cluster popup.',
    askSelection: 'Ask for a recommendation',
    questionLabel: 'Technical question',
    placeholder: 'Ask a technical question. The assistant answers from road-pathology manuals, not from live observations.',
    passages: 'Passages',
    passagesHelp: 'Number of manual excerpts sent to the model.',
    submit: 'Search the manuals',
    loading: 'Searching the manuals and drafting an answer… This can take a minute.',
    empty: 'No answer yet. The manuals are queried only when you ask.',
    sent: 'Question sent',
    answer: 'Answer',
    sources: 'Sources',
    noSources: 'No passage was returned with this answer.',
    score: 'Score',
    disclaimer: 'The answer is generated from the manuals. Check the sources before a technical decision.',
    unclassified: 'Unclassified',
    unknownPriority: 'Priority not recorded',
    unknownStatus: 'Status not recorded',
  },
};

function selectionLine(selection, lang, copy) {
  if (!selection) return null;
  const known = selection.classCode && DAMAGE_CLASSES[selection.classCode];
  const classText = known
    ? `${known.code} · ${lang === 'fr' ? known.fr : known.en}`
    : copy.unclassified;
  const priority = selection.priority || copy.unknownPriority;
  const status = selection.status && STATUS_LABELS[selection.status]
    ? (lang === 'fr' ? STATUS_LABELS[selection.status].fr : STATUS_LABELS[selection.status].en)
    : copy.unknownStatus;
  return `${classText} · ${priority} · ${status}`;
}

export function TechnicalRecommendation({ lang = 'fr', selection = null, request = null }) {
  const copy = COPY[lang] || COPY.fr;
  const configured = isRagConfigured();
  const [k, setK] = useState(RAG_K_DEFAULT);
  const [draft, setDraft] = useState('');
  const [phase, setPhase] = useState('idle');
  const [asked, setAsked] = useState('');
  const [result, setResult] = useState(null);
  const [error, setError] = useState(null);
  const runId = useRef(0);
  const abortRef = useRef(null);
  const kRef = useRef(k);
  kRef.current = k;

  async function run(question, passages) {
    abortRef.current?.abort();
    const controller = new AbortController();
    abortRef.current = controller;
    const id = ++runId.current;
    setPhase('loading');
    setError(null);
    setResult(null);
    setAsked(String(question || '').trim());
    const response = await askRag({
      question,
      k: passages,
      signal: controller.signal,
      configured,
    });
    if (id !== runId.current || response.error?.code === 'aborted') return;
    if (response.ok) {
      setResult(response);
      setPhase('ready');
      return;
    }
    setError(response.error);
    setPhase('error');
  }

  useEffect(() => {
    if (!request?.question) return undefined;
    run(request.question, kRef.current);
    return () => abortRef.current?.abort();
    // Re-ask only when a new observation request arrives.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [request]);

  function onSubmit(event) {
    event.preventDefault();
    run(draft, k);
  }

  const summary = selectionLine(selection, lang, copy);

  return (
    <section id="recommandation-technique" className="rag-panel" aria-labelledby="rag-title">
      <div className="rag-heading">
        <BookOpen size={18} aria-hidden="true" />
        <div>
          <h2 id="rag-title">{copy.title}</h2>
          <p>{copy.intro}</p>
        </div>
      </div>

      {!configured && (
        <p className="rag-unavailable" role="status">{copy.unavailable}</p>
      )}

      <div className="rag-selected">
        <p className="rag-kicker">{copy.selected}</p>
        <p>{summary || copy.none}</p>
        <button
          type="button"
          className="btn btn-primary"
          disabled={!configured || !selection || phase === 'loading'}
          onClick={() => selection && run(buildTechnicalQuestion(selection, lang), k)}
        >
          {copy.askSelection}
        </button>
      </div>

      <form className="rag-form" onSubmit={onSubmit}>
        <label htmlFor="rag-question">
          <span>{copy.questionLabel}</span>
          <textarea
            id="rag-question"
            value={draft}
            disabled={!configured || phase === 'loading'}
            placeholder={copy.placeholder}
            onChange={(event) => setDraft(event.target.value)}
          />
        </label>
        <div className="rag-controls">
          <label htmlFor="rag-k">
            <span>{copy.passages}</span>
            <select
              id="rag-k"
              value={k}
              disabled={!configured || phase === 'loading'}
              onChange={(event) => setK(Number(event.target.value))}
            >
              {Array.from({ length: RAG_K_MAX - RAG_K_MIN + 1 }, (_, index) => RAG_K_MIN + index).map((value) => (
                <option key={value} value={value}>{value}</option>
              ))}
            </select>
          </label>
          <button type="submit" className="btn btn-secondary" disabled={!configured || phase === 'loading'}>
            {copy.submit}
          </button>
          <p className="rag-help">{copy.passagesHelp}</p>
        </div>
      </form>

      {asked && phase !== 'idle' && (
        <p className="rag-sent"><span>{copy.sent}</span> {asked}</p>
      )}
      {phase === 'loading' && <p className="rag-loading" role="status">{copy.loading}</p>}
      {phase === 'error' && error && error.code !== 'not_configured' && (
        <p className="rag-error" role="alert">{error.message}</p>
      )}
      {phase === 'idle' && configured && <p className="rag-empty">{copy.empty}</p>}

      {phase === 'ready' && result && (
        <article className="rag-result">
          <h3>{copy.answer}</h3>
          <p className="rag-answer">{result.answer}</p>
          <h3>{copy.sources} ({result.sources.length})</h3>
          {result.sources.length === 0 ? (
            <p className="rag-empty">{copy.noSources}</p>
          ) : (
            <ul className="rag-sources">
              {result.sources.map((source, index) => (
                <li key={`${source.source}-${index}`} className="rag-source">
                  <div className="rag-source-top">
                    <strong title={source.source}>{sourceFileName(source.source)}</strong>
                    <span>{copy.score} {source.score.toFixed(3)}</span>
                  </div>
                  <div className="rag-score-bar" aria-hidden="true">
                    <span style={{ width: `${Math.max(0, Math.min(source.score, 1)) * 100}%` }} />
                  </div>
                  <p className="rag-excerpt">{source.excerpt || source.text}</p>
                </li>
              ))}
            </ul>
          )}
          <p className="rag-disclaimer">{copy.disclaimer}</p>
        </article>
      )}
    </section>
  );
}
