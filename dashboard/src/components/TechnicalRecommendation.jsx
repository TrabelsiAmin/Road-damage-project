import React, { useEffect, useRef, useState } from 'react';
import { BookOpen } from 'lucide-react';
import { DAMAGE_CLASSES, STATUS_LABELS } from '../constants';
import {
  COLAB_DEMONSTRATION,
  RAG_CONNECT_NOTE,
  RAG_K_DEFAULT,
  RAG_K_MAX,
  RAG_K_MIN,
  askRag,
  checkRagHealth,
  isRagConfigured,
  readStoredRagBase,
  shouldShowColabDemonstration,
  sourceFileName,
  writeStoredRagBase,
} from '../utils/ragClient';
import { recommendationForRetained } from '../utils/retainedObservation';

const COPY = {
  fr: {
    title: 'Recommandation technique',
    intro: 'L\'assistant répond à partir des manuels de pathologie routière. Il ne lit pas les observations en direct et ne reçoit ni photo, ni coordonnée, ni identifiant d\'appareil.',
    urlLabel: 'API sur cet ordinateur',
    urlPlaceholder: 'http://127.0.0.1:8000',
    saveUrl: 'Enregistrer',
    needUrl: RAG_CONNECT_NOTE.fr,
    badUrl: 'Cette adresse n\'est pas une URL http(s).',
    demoKicker: 'Démonstration Colab',
    demoCaption: 'Réponses enregistrées dans le notebook Colab. Pas une requête en direct.',
    demoQuestion: 'Question',
    demoAnswer: 'Réponse',
    refusal: 'Refus',
    selected: 'Observation retenue',
    none: 'Choisissez une observation dans la file prioritaire ou dans l\'infobulle d\'un agrégat sur la carte.',
    askSelection: 'Demander une recommandation',
    questionLabel: 'Question technique',
    placeholder: 'Posez une question technique. L\'assistant répond à partir des manuels de pathologie routière, pas à partir des observations en direct.',
    passages: 'Passages',
    passagesHelp: 'Nombre d\'extraits de manuels transmis au modèle.',
    submit: 'Envoyer',
    examples: 'Exemples de questions',
    examplesHelp: 'Un clic remplit la question. La réponse vient du modèle sur cet ordinateur.',
    checking: 'Vérification de l\'assistant…',
    ready: 'L\'assistant est prêt.',
    loading: 'Recherche dans les manuels et rédaction de la réponse… Cela peut prendre une minute.',
    empty: 'Aucune réponse à afficher. Les manuels ne sont interrogés qu\'à votre demande.',
    sent: 'Question envoyée',
    answer: 'Réponse',
    sources: 'Sources',
    noSources: 'Aucun passage n\'a été renvoyé avec cette réponse.',
    topSource: 'Source principale',
    score: 'Score',
    disclaimer: 'Réponse rédigée par un modèle à partir des manuels. Vérifiez les sources avant toute décision technique.',
    unclassified: 'Non classé',
    unknownPlace: 'Lieu non renseigné',
    unknownDate: 'Date non renseignée',
    unknownStatus: 'Statut non renseigné',
    notLive: 'Ce n\'est pas un appel en direct. Réponse enregistrée de la démonstration Colab.',
    colabRequired: 'L\'adresse Colab est requise pour répondre à cette observation.',
  },
  en: {
    title: 'Technical recommendation',
    intro: 'The assistant answers from road-pathology manuals. It does not read live observations and is not sent photos, coordinates, or device identifiers.',
    urlLabel: 'API on this computer',
    urlPlaceholder: 'http://127.0.0.1:8000',
    saveUrl: 'Save',
    needUrl: RAG_CONNECT_NOTE.en,
    badUrl: 'This is not an http(s) URL.',
    demoKicker: 'Colab demonstration',
    demoCaption: 'Answers recorded in the Colab notebook. Not a live query.',
    demoQuestion: 'Question',
    demoAnswer: 'Answer',
    refusal: 'Refusal',
    selected: 'Selected observation',
    none: 'Choose an observation in the priority list or in a map cluster popup.',
    askSelection: 'Ask for a recommendation',
    questionLabel: 'Technical question',
    placeholder: 'Ask a technical question. The assistant answers from road-pathology manuals, not from live observations.',
    passages: 'Passages',
    passagesHelp: 'Number of manual excerpts sent to the model.',
    submit: 'Send',
    examples: 'Example questions',
    examplesHelp: 'A click fills the question. The answer comes from the model on this computer.',
    checking: 'Checking the assistant…',
    ready: 'The assistant is ready.',
    loading: 'Searching the manuals and drafting an answer… This can take a minute.',
    empty: 'No answer yet. The manuals are queried only when you ask.',
    sent: 'Question sent',
    answer: 'Answer',
    sources: 'Sources',
    noSources: 'No passage was returned with this answer.',
    topSource: 'Top source',
    score: 'Score',
    disclaimer: 'The answer is generated from the manuals. Check the sources before a technical decision.',
    unclassified: 'Unclassified',
    unknownPlace: 'Place not recorded',
    unknownDate: 'Date not recorded',
    unknownStatus: 'Status not recorded',
    notLive: 'This is not a live call. Answer recorded from the Colab demonstration.',
    colabRequired: 'The Colab address is required to answer this observation.',
  },
};

function sameOriginRagBase() {
  if (!isRagConfigured()) return '';
  try {
    return `${window.location.origin}/rag`;
  } catch {
    return '';
  }
}

function selectionLine(selection, lang, copy) {
  if (!selection) return null;
  const known = selection.classCode && DAMAGE_CLASSES[selection.classCode];
  const classText = known ? known.code : copy.unclassified;
  const place = selection.place || copy.unknownPlace;
  const date = selection.dateLabel || copy.unknownDate;
  const status = selection.status && STATUS_LABELS[selection.status]
    ? (lang === 'fr' ? STATUS_LABELS[selection.status].fr : STATUS_LABELS[selection.status].en)
    : copy.unknownStatus;
  return `${classText} · ${place} · ${date} · ${status}`;
}

export function TechnicalRecommendation({ lang = 'fr', selection = null, request = null }) {
  const copy = COPY[lang] || COPY.fr;
  const [k, setK] = useState(RAG_K_DEFAULT);
  const [urlDraft, setUrlDraft] = useState(() => readStoredRagBase());
  const [base, setBase] = useState(() => readStoredRagBase());
  const [draft, setDraft] = useState('');
  const [phase, setPhase] = useState('idle');
  const [asked, setAsked] = useState('');
  const [result, setResult] = useState(null);
  const [error, setError] = useState(null);
  const [liveBase, setLiveBase] = useState('');
  const [backend, setBackend] = useState(() => (
    readStoredRagBase() || isRagConfigured() ? 'checking' : 'down'
  ));
  const runId = useRef(0);
  const abortRef = useRef(null);
  const cardRun = useRef(0);
  const cardAbort = useRef(null);
  const [cardPhase, setCardPhase] = useState('idle');
  const [cardResult, setCardResult] = useState(null);
  const [cardNote, setCardNote] = useState('');
  const kRef = useRef(k);
  const baseRef = useRef('');
  kRef.current = k;
  baseRef.current = liveBase;

  useEffect(() => {
    const candidates = [];
    if (base) candidates.push(base);
    const proxy = sameOriginRagBase();
    if (proxy && proxy !== base) candidates.push(proxy);
    if (candidates.length === 0) {
      setLiveBase('');
      setBackend('down');
      return undefined;
    }
    let cancelled = false;
    setBackend('checking');
    (async () => {
      for (const candidate of candidates) {
        const status = await checkRagHealth({ base: candidate });
        if (cancelled) return;
        if (status.ok) {
          setLiveBase(candidate);
          setBackend('up');
          return;
        }
      }
      if (!cancelled) {
        setLiveBase('');
        setBackend('down');
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [base]);

  function saveUrl(event) {
    event?.preventDefault();
    const next = writeStoredRagBase(urlDraft);
    if (!next && String(urlDraft || '').trim()) {
      setBase('');
      setUrlDraft(String(urlDraft || '').trim());
      setResult(null);
      setError({ code: 'bad_url', message: copy.badUrl });
      setPhase('error');
      return;
    }
    setUrlDraft(next);
    setBase(next);
    if (phase === 'error' && error?.code === 'bad_url') {
      setError(null);
      setPhase('idle');
    }
  }

  async function run(question, passages) {
    const trimmed = String(question || '').trim();
    const root = baseRef.current;
    setAsked(trimmed);
    if (!root) {
      abortRef.current?.abort();
      runId.current += 1;
      setResult(null);
      setError({ code: 'not_configured', message: copy.needUrl });
      setPhase(trimmed ? 'error' : 'idle');
      return;
    }
    abortRef.current?.abort();
    const controller = new AbortController();
    abortRef.current = controller;
    const id = ++runId.current;
    setPhase('loading');
    setError(null);
    setResult(null);
    const response = await askRag({
      question: trimmed,
      k: passages,
      base: root,
      signal: controller.signal,
    });
    if (id !== runId.current || response.error?.code === 'aborted') return;
    if (response.ok) {
      setResult(response);
      setPhase('ready');
      setBackend('up');
      return;
    }
    if (response.error?.code === 'unavailable' || response.error?.code === 'network' || response.error?.code === 'timeout') {
      setLiveBase('');
      setBackend('down');
    }
    setError(response.error);
    setPhase('error');
  }

  useEffect(() => {
    setCardPhase('idle');
    setCardResult(null);
    setCardNote('');
  }, [selection]);

  async function askRetained() {
    if (!selection) return;
    cardAbort.current?.abort();
    const controller = new AbortController();
    cardAbort.current = controller;
    const id = ++cardRun.current;
    setCardPhase('loading');
    setCardResult(null);
    setCardNote('');
    const outcome = await recommendationForRetained({
      observation: selection,
      lang,
      storedBase: baseRef.current || readStoredRagBase(),
      k: kRef.current,
      signal: controller.signal,
    });
    if (id !== cardRun.current || outcome.error?.code === 'aborted') return;
    if (outcome.ok && outcome.live) {
      setCardResult(outcome);
      setCardPhase('ready');
      return;
    }
    if (outcome.recorded) {
      setCardResult(outcome);
      setCardNote(copy.notLive);
      setCardPhase('recorded');
      return;
    }
    setCardResult(null);
    setCardNote(copy.colabRequired);
    setCardPhase('error');
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
  const busy = phase === 'loading';
  const topSource = result?.sources?.[0];
  const showDemo = shouldShowColabDemonstration({ backend });

  return (
    <section id="recommandation-technique" className="rag-panel" aria-labelledby="rag-title" data-assistant-panel="true">
      <div className="rag-heading">
        <BookOpen size={18} aria-hidden="true" />
        <div>
          <h2 id="rag-title">{copy.title}</h2>
          <p>{copy.intro}</p>
        </div>
      </div>

      {showDemo && (
        <div className="rag-demo" data-colab-demonstration="recorded">
          <p className="rag-demo-note" role="status">{copy.needUrl}</p>
          <p className="rag-kicker">{copy.demoKicker}</p>
          <p className="rag-demo-caption">{copy.demoCaption}</p>
          <ol className="rag-demo-list">
            {COLAB_DEMONSTRATION.map((item, index) => (
              <li key={item.question} className={item.refusal ? 'rag-demo-item is-refusal' : 'rag-demo-item'}>
                <p className="rag-demo-q">
                  <span>{copy.demoQuestion} {index + 1}</span>
                  {item.question}
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
            ))}
          </ol>
        </div>
      )}

      <form className="rag-url" onSubmit={saveUrl}>
        <div className="rag-url-row">
          <label htmlFor="rag-api-url">
            <span>{copy.urlLabel}</span>
            <input
              id="rag-api-url"
              name="tariqmap_rag_url"
              type="text"
              inputMode="url"
              autoComplete="off"
              spellCheck="false"
              placeholder={copy.urlPlaceholder}
              value={urlDraft}
              data-assistant-url="true"
              onChange={(event) => setUrlDraft(event.target.value)}
            />
          </label>
          <button type="submit" className="btn btn-secondary">{copy.saveUrl}</button>
        </div>
      </form>

      {backend === 'checking' && (
        <p className="rag-loading" role="status">{copy.checking}</p>
      )}
      {backend === 'up' && (
        <p className="rag-loading" role="status">{copy.ready}</p>
      )}
      {backend === 'up' && (
        <div className="rag-examples">
          <p className="rag-kicker">{copy.examples}</p>
          <p className="rag-demo-caption">{copy.examplesHelp}</p>
          <ul className="rag-example-list">
            {COLAB_DEMONSTRATION.map((item) => (
              <li key={item.question}>
                <button
                  type="button"
                  className="rag-example"
                  onClick={() => setDraft(item.question)}
                >
                  {item.question}
                </button>
              </li>
            ))}
          </ul>
        </div>
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
          <label htmlFor="rag-k">
            <span>{copy.passages}</span>
            <select
              id="rag-k"
              value={k}
              disabled={busy}
              onChange={(event) => setK(Number(event.target.value))}
            >
              {Array.from({ length: RAG_K_MAX - RAG_K_MIN + 1 }, (_, index) => RAG_K_MIN + index).map((value) => (
                <option key={value} value={value}>{value}</option>
              ))}
            </select>
          </label>
          <button type="submit" className="btn btn-primary" disabled={busy}>
            {copy.submit}
          </button>
          <p className="rag-help">{copy.passagesHelp}</p>
        </div>
      </form>

      {asked && phase !== 'idle' && (
        <p className="rag-sent"><span>{copy.sent}</span> {asked}</p>
      )}
      {phase === 'loading' && <p className="rag-loading" role="status">{copy.loading}</p>}
      {phase === 'error' && error && !(showDemo && ['not_configured', 'unavailable', 'network', 'timeout'].includes(error.code)) && (
        <p className="rag-error" role="alert">{error.message}</p>
      )}
      {phase === 'idle' && backend === 'up' && <p className="rag-empty">{copy.empty}</p>}

      {phase === 'ready' && result && (
        <article className="rag-result" data-assistant-answer="true">
          <h3>{copy.answer}</h3>
          <p className="rag-answer">{result.answer}</p>
          {topSource && (
            <p className="rag-top-source" data-assistant-source="true">
              <span>{copy.topSource}</span>
              <strong title={topSource.source}>{sourceFileName(topSource.source)}</strong>
              <em>{copy.score} {Number(topSource.score).toFixed(4)}</em>
            </p>
          )}
          <h3>{copy.sources} ({result.sources.length})</h3>
          {result.sources.length === 0 ? (
            <p className="rag-empty">{copy.noSources}</p>
          ) : (
            <ul className="rag-sources">
              {result.sources.map((source, index) => (
                <li key={`${source.source}-${index}`} className="rag-source">
                  <div className="rag-source-top">
                    <strong title={source.source}>{sourceFileName(source.source)}</strong>
                    <span>{copy.score} {source.score.toFixed(4)}</span>
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

      <div className="rag-selected" data-retained-observation="true">
        <p className="rag-kicker">{copy.selected}</p>
        <p data-retained-summary="true">{summary || copy.none}</p>
        <button
          type="button"
          className="btn btn-secondary"
          data-retained-ask="true"
          disabled={!selection || cardPhase === 'loading'}
          onClick={askRetained}
        >
          {copy.askSelection}
        </button>
        {cardPhase === 'loading' && (
          <p className="rag-loading" role="status">{copy.loading}</p>
        )}
        {cardNote && (
          <p className="rag-connect" role="status" data-retained-note="true">{cardNote}</p>
        )}
        {cardResult && (
          <div data-retained-answer="true">
            <h3>{copy.answer}</h3>
            <p className="rag-answer">{cardResult.answer}</p>
            {cardResult.sources?.[0] && (
              <p className="rag-top-source" data-retained-source="true">
                <span>{copy.topSource}</span>
                <strong title={cardResult.sources[0].source}>{sourceFileName(cardResult.sources[0].source)}</strong>
                <em>{copy.score} {Number(cardResult.sources[0].score).toFixed(4)}</em>
              </p>
            )}
          </div>
        )}
      </div>
    </section>
  );
}
