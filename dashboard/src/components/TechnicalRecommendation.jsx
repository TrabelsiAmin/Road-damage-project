import React, { useEffect, useRef, useState } from 'react';
import { BookOpen } from 'lucide-react';
import { DAMAGE_CLASSES, STATUS_LABELS } from '../constants';
import {
  COLAB_DEMONSTRATION,
  RAG_ASK_PATH,
  RAG_K_DEFAULT,
  RAG_K_MAX,
  RAG_K_MIN,
  RAG_REMOTE_NOTE,
  askRag,
  buildTechnicalQuestion,
  checkThisMachineRag,
  findColabDemonstration,
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
    submit: 'Envoyer',
    session: 'Session Colab',
    sessionNote: 'Réponse enregistrée de cette session Colab. Pas un appel en direct.',
    notRecorded: 'Cette question ne figure pas dans la session Colab enregistrée. Aucune réponse n\'est inventée.',
    checking: 'Vérification de l\'assistant…',
    ready: 'L\'assistant est prêt.',
    down: RAG_REMOTE_NOTE.fr,
    demoKicker: 'Démonstration Colab',
    demoCaption: 'Réponses enregistrées dans le notebook Colab. Pas une requête en direct.',
    demoQuestion: 'Question',
    demoAnswer: 'Réponse',
    topSource: 'Source principale',
    refusal: 'Refus',
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
    submit: 'Send',
    session: 'Colab session',
    sessionNote: 'Answer recorded from that Colab session. Not a live call.',
    notRecorded: 'This question is not in the recorded Colab session. No answer is invented.',
    checking: 'Checking the assistant…',
    ready: 'The assistant is ready.',
    down: RAG_REMOTE_NOTE.en,
    demoKicker: 'Colab demonstration',
    demoCaption: 'Answers recorded in the Colab notebook. Not a live query.',
    demoQuestion: 'Question',
    demoAnswer: 'Answer',
    topSource: 'Top source',
    refusal: 'Refusal',
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
  const classText = known ? known.code : copy.unclassified;
  const priority = selection.priority || copy.unknownPriority;
  const status = selection.status && STATUS_LABELS[selection.status]
    ? (lang === 'fr' ? STATUS_LABELS[selection.status].fr : STATUS_LABELS[selection.status].en)
    : copy.unknownStatus;
  return `${classText} · ${priority} · ${status}`;
}

function recordedResult(item) {
  return {
    recorded: true,
    answer: item.answer,
    sources: [{ source: item.source, score: item.score, text: '', excerpt: '' }],
  };
}

export function TechnicalRecommendation({ lang = 'fr', selection = null, request = null }) {
  const copy = COPY[lang] || COPY.fr;
  const [k, setK] = useState(RAG_K_DEFAULT);
  const [draft, setDraft] = useState('');
  const [phase, setPhase] = useState('idle');
  const [asked, setAsked] = useState('');
  const [result, setResult] = useState(null);
  const [error, setError] = useState(null);
  const [backend, setBackend] = useState('checking');
  const runId = useRef(0);
  const abortRef = useRef(null);
  const kRef = useRef(k);
  const livePathRef = useRef(RAG_ASK_PATH);
  const backendRef = useRef(backend);
  kRef.current = k;
  backendRef.current = backend;

  useEffect(() => {
    let cancelled = false;
    setBackend('checking');
    checkThisMachineRag().then((status) => {
      if (cancelled) return;
      if (status.ok) {
        livePathRef.current = status.path || RAG_ASK_PATH;
        setBackend('up');
        return;
      }
      setBackend('down');
    });
    return () => {
      cancelled = true;
    };
  }, []);

  function fillRecorded(item) {
    abortRef.current?.abort();
    runId.current += 1;
    setDraft(item.question);
    setAsked(item.question);
    setError(null);
    setResult(recordedResult(item));
    setPhase('recorded');
  }

  async function run(question, passages) {
    const trimmed = String(question || '').trim();
    if (backendRef.current !== 'up') {
      const recorded = findColabDemonstration(trimmed);
      if (recorded) {
        fillRecorded(recorded);
        return;
      }
      setAsked(trimmed);
      setResult(null);
      setPhase(trimmed ? 'error' : 'idle');
      setError(trimmed ? { code: 'not_recorded', message: copy.notRecorded } : null);
      return;
    }
    abortRef.current?.abort();
    const controller = new AbortController();
    abortRef.current = controller;
    const id = ++runId.current;
    setPhase('loading');
    setError(null);
    setResult(null);
    setAsked(trimmed);
    const response = await askRag({
      question: trimmed,
      k: passages,
      signal: controller.signal,
      configured: true,
      path: livePathRef.current,
    });
    if (id !== runId.current || response.error?.code === 'aborted') return;
    if (response.ok) {
      setResult(response);
      setPhase('ready');
      return;
    }
    const recorded = findColabDemonstration(trimmed);
    setBackend('down');
    backendRef.current = 'down';
    if (recorded) {
      fillRecorded(recorded);
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
  const showDemo = backend === 'down';
  const live = backend === 'up';
  const busy = backend === 'checking' || phase === 'loading';
  const topSource = result?.sources?.[0];

  return (
    <section id="recommandation-technique" className="rag-panel" aria-labelledby="rag-title" data-assistant-panel="true">
      <div className="rag-heading">
        <BookOpen size={18} aria-hidden="true" />
        <div>
          <h2 id="rag-title">{copy.title}</h2>
          <p>{copy.intro}</p>
        </div>
      </div>

      {backend === 'checking' && (
        <p className="rag-loading" role="status">{copy.checking}</p>
      )}
      {live && (
        <p className="rag-loading" role="status">{copy.ready}</p>
      )}
      {showDemo && (
        <p className="rag-demo-note" role="status">{copy.down}</p>
      )}

      <form className="rag-form" onSubmit={onSubmit}>
        <label htmlFor="rag-question">
          <span>{copy.questionLabel}</span>
          <textarea
            id="rag-question"
            value={draft}
            disabled={busy}
            placeholder={copy.placeholder}
            onChange={(event) => setDraft(event.target.value)}
          />
        </label>
        <div className="rag-controls">
          {live && (
            <label htmlFor="rag-k">
              <span>{copy.passages}</span>
              <select
                id="rag-k"
                value={k}
                disabled={phase === 'loading'}
                onChange={(event) => setK(Number(event.target.value))}
              >
                {Array.from({ length: RAG_K_MAX - RAG_K_MIN + 1 }, (_, index) => RAG_K_MIN + index).map((value) => (
                  <option key={value} value={value}>{value}</option>
                ))}
              </select>
            </label>
          )}
          <button type="submit" className="btn btn-primary" disabled={busy}>
            {copy.submit}
          </button>
          {live && <p className="rag-help">{copy.passagesHelp}</p>}
        </div>
      </form>

      {asked && phase !== 'idle' && (
        <p className="rag-sent"><span>{copy.sent}</span> {asked}</p>
      )}
      {phase === 'loading' && <p className="rag-loading" role="status">{copy.loading}</p>}
      {phase === 'error' && error && (
        <p className="rag-error" role="alert">{error.message}</p>
      )}
      {phase === 'idle' && live && <p className="rag-empty">{copy.empty}</p>}

      {(phase === 'ready' || phase === 'recorded') && result && (
        <article className="rag-result" data-assistant-answer="true">
          {result.recorded && (
            <>
              <p className="rag-kicker">{copy.session}</p>
              <p className="rag-demo-caption">{copy.sessionNote}</p>
            </>
          )}
          <h3>{copy.answer}</h3>
          <p className="rag-answer">{result.answer}</p>
          {result.recorded && topSource ? (
            <p className="rag-demo-source" data-assistant-source="true">
              <span>{copy.topSource}</span>
              <strong title={topSource.source}>{sourceFileName(topSource.source)}</strong>
              <em>{copy.score} {topSource.score.toFixed(4)}</em>
            </p>
          ) : (
            <>
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
            </>
          )}
        </article>
      )}

      {showDemo && (
        <div className="rag-demo">
          <p className="rag-kicker">{copy.demoKicker}</p>
          <p className="rag-demo-caption">{copy.demoCaption}</p>
          <ol className="rag-demo-list">
            {COLAB_DEMONSTRATION.map((item, index) => {
              const selected = phase === 'recorded' && asked === item.question;
              return (
                <li key={item.question} className={item.refusal ? 'rag-demo-item is-refusal' : 'rag-demo-item'}>
                  <p className="rag-demo-q">
                    <span>{copy.demoQuestion} {index + 1}</span>
                    <button
                      type="button"
                      className="rag-demo-pick"
                      aria-pressed={selected}
                      onClick={() => fillRecorded(item)}
                    >
                      {item.question}
                    </button>
                  </p>
                  {item.refusal && <p className="rag-demo-refusal">{copy.refusal}</p>}
                  <p className="rag-demo-a">
                    <span>{copy.demoAnswer}</span>
                    {item.answer}
                  </p>
                  <p className="rag-demo-source">
                    <span>{copy.topSource}</span>
                    <strong title={item.source}>{sourceFileName(item.source)}</strong>
                    <em>{copy.score} {item.score.toFixed(4)}</em>
                  </p>
                </li>
              );
            })}
          </ol>
        </div>
      )}

      <div className="rag-selected">
        <p className="rag-kicker">{copy.selected}</p>
        <p>{summary || copy.none}</p>
        <button
          type="button"
          className="btn btn-secondary"
          disabled={!live || !selection || phase === 'loading'}
          onClick={() => selection && run(buildTechnicalQuestion(selection, lang), k)}
        >
          {copy.askSelection}
        </button>
      </div>
    </section>
  );
}
