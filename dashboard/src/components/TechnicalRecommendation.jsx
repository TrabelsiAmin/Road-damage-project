import React, { useEffect, useRef, useState } from 'react';
import { BookOpen } from 'lucide-react';
import { DAMAGE_CLASSES, STATUS_LABELS } from '../constants';
import {
  LOCAL_EXTRACT_BASE,
  RAG_K_DEFAULT,
  askRag,
  buildTechnicalQuestion,
  chooseAssistantBase,
  normalizeRagBase,
  readStoredRagBase,
  sourceFileName,
  writeStoredRagBase,
} from '../utils/ragClient';
import { recommendationForRetained } from '../utils/retainedObservation';

const COPY = {
  fr: {
    title: 'Recommandation technique',
    intro: 'Posez une question. L\'assistant répond à partir des manuels indexés, à l\'adresse enregistrée.',
    urlLabel: 'Adresse de l\'API Colab',
    urlPlaceholder: 'https://….ngrok-free.app',
    saveUrl: 'Enregistrer',
    badUrl: 'Cette adresse n\'est pas une URL http(s).',
    apiDown: 'l\'API ne répond pas',
    tunnelDown: 'La session Colab est arrêtée : le tunnel est fermé.',
    localNote: 'La session Colab est arrêtée : le tunnel est fermé. Les questions partent vers les extraits des manuels sur cette machine, sans le modèle Qwen.',
    localOnly: 'Aucune adresse Colab n\'est enregistrée. Les questions partent vers les extraits des manuels sur cette machine, sans le modèle Qwen.',
    emptyLocal: 'Le fil est vide. L\'adresse Colab ne répond pas : la question part vers les extraits locaux des manuels.',
    httpError: 'Erreur HTTP',
    selected: 'Observation retenue',
    none: 'Choisissez une observation dans la file prioritaire ou dans l\'infobulle d\'un agrégat sur la carte.',
    askSelection: 'Demander une recommandation',
    questionLabel: 'Question',
    placeholder: 'Écrivez une question.',
    submit: 'Envoyer',
    checking: 'Vérification de l\'assistant…',
    ready: 'L\'assistant est prêt.',
    loading: 'Recherche dans les manuels…',
    empty: 'Le fil est vide. Chaque question est envoyée à l\'adresse enregistrée.',
    you: 'Vous',
    answer: 'Assistant',
    topSource: 'Manuel',
    score: 'Score',
    disclaimer: 'Réponse rédigée à partir des manuels indexés.',
    unclassified: 'Non classé',
    unknownPlace: 'Lieu non renseigné',
    unknownDate: 'Date non renseignée',
    unknownStatus: 'Statut non renseigné',
  },
  en: {
    title: 'Technical recommendation',
    intro: 'Ask a question. The assistant answers from the indexed manuals at the saved address.',
    urlLabel: 'Colab API address',
    urlPlaceholder: 'https://….ngrok-free.app',
    saveUrl: 'Save',
    badUrl: 'This is not an http(s) URL.',
    apiDown: 'The API is not responding',
    tunnelDown: 'The Colab session is stopped: the tunnel is closed.',
    localNote: 'The Colab session is stopped: the tunnel is closed. Questions go to the manual excerpts on this machine, without the Qwen model.',
    localOnly: 'No Colab address is saved. Questions go to the manual excerpts on this machine, without the Qwen model.',
    emptyLocal: 'The thread is empty. The Colab address is not responding: the question goes to the local manual excerpts.',
    httpError: 'HTTP error',
    selected: 'Selected observation',
    none: 'Choose an observation in the priority list or in a map cluster popup.',
    askSelection: 'Ask for a recommendation',
    questionLabel: 'Question',
    placeholder: 'Type a question.',
    submit: 'Send',
    checking: 'Checking the assistant…',
    ready: 'The assistant is ready.',
    loading: 'Searching the manuals…',
    empty: 'The thread is empty. Each question is sent to the saved address.',
    you: 'You',
    answer: 'Assistant',
    topSource: 'Manual',
    score: 'Score',
    disclaimer: 'Answer written from the indexed manuals.',
    unclassified: 'Unclassified',
    unknownPlace: 'Place not recorded',
    unknownDate: 'Date not recorded',
    unknownStatus: 'Status not recorded',
  },
};

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

function failureText(error, copy) {
  if (error?.status) return `${copy.httpError} ${error.status}`;
  if (error?.message) return error.message;
  return copy.apiDown;
}

export function TechnicalRecommendation({ lang = 'fr', selection = null, request = null }) {
  const copy = COPY[lang] || COPY.fr;
  const [urlDraft, setUrlDraft] = useState(() => readStoredRagBase());
  const [base, setBase] = useState(() => readStoredRagBase());
  const [draft, setDraft] = useState('');
  const [phase, setPhase] = useState('idle');
  const [messages, setMessages] = useState([]);
  const [urlError, setUrlError] = useState('');
  const [route, setRoute] = useState('checking');
  const [routeNote, setRouteNote] = useState('');
  const runId = useRef(0);
  const abortRef = useRef(null);
  const cardRun = useRef(0);
  const baseRef = useRef(base);
  const [cardPhase, setCardPhase] = useState('idle');
  const [cardResult, setCardResult] = useState(null);
  const [cardNote, setCardNote] = useState('');
  baseRef.current = base;

  const applyChoice = (choice, saved) => {
    if (choice.ok && choice.via === 'saved') {
      setRoute('saved');
      setRouteNote('');
      return;
    }
    if (choice.ok && choice.via === 'local') {
      setRoute('local');
      setRouteNote(saved ? copy.localNote : copy.localOnly);
      return;
    }
    setRoute(saved ? 'down' : 'idle');
    setRouteNote(saved ? (choice.error?.message || copy.tunnelDown) : '');
  };

  useEffect(() => {
    let cancelled = false;
    setRoute('checking');
    chooseAssistantBase({ base, localBase: LOCAL_EXTRACT_BASE }).then((choice) => {
      if (cancelled) return;
      applyChoice(choice, base);
    });
    return () => {
      cancelled = true;
    };
  }, [base, copy.localNote, copy.localOnly, copy.tunnelDown]);

  function saveUrl(event) {
    event?.preventDefault();
    const trimmed = String(urlDraft || '').trim();
    if (!trimmed) {
      setUrlDraft(base);
      setUrlError('');
      return;
    }
    const next = normalizeRagBase(trimmed);
    if (!next) {
      setUrlError(copy.badUrl);
      return;
    }
    writeStoredRagBase(next);
    setUrlError('');
    setUrlDraft(next);
    setBase(next);
  }

  function appendExchange(id, question, reply) {
    setMessages((prev) => [
      ...prev,
      { id: `${id}-q`, role: 'user', text: question },
      { id: `${id}-a`, role: 'assistant', ...reply },
    ]);
  }

  async function resolveTarget() {
    const saved = baseRef.current;
    const choice = await chooseAssistantBase({
      base: saved,
      localBase: LOCAL_EXTRACT_BASE,
    });
    applyChoice(choice, saved);
    return choice;
  }

  async function run(question) {
    const trimmed = String(question || '').trim();
    if (!trimmed) return null;
    abortRef.current?.abort();
    const controller = new AbortController();
    abortRef.current = controller;
    const id = ++runId.current;
    setPhase('loading');
    setDraft('');
    const choice = await resolveTarget();
    if (id !== runId.current) return null;
    if (!choice.ok) {
      const message = choice.error?.message || copy.apiDown;
      appendExchange(id, trimmed, { error: message });
      setPhase('error');
      return { ok: false, error: choice.error || { code: 'unavailable', message } };
    }
    const response = await askRag({
      question: trimmed,
      k: RAG_K_DEFAULT,
      base: choice.base,
      signal: controller.signal,
      checkHealth: false,
    });
    if (id !== runId.current || response.error?.code === 'aborted') return response;
    if (response.ok) {
      const top = response.sources?.[0];
      appendExchange(id, trimmed, {
        text: response.answer,
        source: top?.source || '',
        score: top?.score,
      });
      setPhase('ready');
      applyChoice(choice, baseRef.current);
      return response;
    }
    appendExchange(id, trimmed, { error: failureText(response.error, copy) });
    if (response.error?.code === 'network' || response.error?.code === 'timeout' || response.error?.code === 'unavailable') {
      setRoute('down');
      setRouteNote(failureText(response.error, copy));
    }
    setPhase('error');
    return response;
  }

  useEffect(() => {
    cardRun.current += 1;
    setCardPhase('idle');
    setCardResult(null);
    setCardNote('');
  }, [selection]);

  async function askRetained() {
    if (!selection) return;
    abortRef.current?.abort();
    const controller = new AbortController();
    abortRef.current = controller;
    const id = ++cardRun.current;
    const exchangeId = ++runId.current;
    setCardPhase('loading');
    setCardResult(null);
    setCardNote('');
    setPhase('loading');
    const saved = baseRef.current || readStoredRagBase();
    const choice = await chooseAssistantBase({
      base: saved,
      localBase: LOCAL_EXTRACT_BASE,
    });
    applyChoice(choice, saved);
    if (!choice.ok) {
      const sentence = choice.error?.message || copy.apiDown;
      appendExchange(exchangeId, buildTechnicalQuestion(selection, lang), { error: sentence });
      setCardNote(sentence);
      setCardPhase('error');
      setPhase('error');
      return;
    }
    const outcome = await recommendationForRetained({
      observation: selection,
      lang,
      storedBase: choice.base,
      k: RAG_K_DEFAULT,
      signal: controller.signal,
    });
    if (id !== cardRun.current || outcome.error?.code === 'aborted') return;
    if (outcome.ok && outcome.live && outcome.answer) {
      const top = outcome.sources?.[0];
      appendExchange(exchangeId, outcome.question, {
        text: outcome.answer,
        source: top?.source || '',
        score: top?.score,
      });
      setCardResult(outcome);
      setCardNote('');
      setCardPhase('ready');
      setPhase('ready');
      applyChoice(choice, saved);
      return;
    }
    const sentence = failureText(outcome.error, copy);
    appendExchange(exchangeId, outcome.question, { error: sentence });
    setCardResult(null);
    setCardNote(sentence);
    setCardPhase('error');
    setPhase('error');
    setRoute('down');
    setRouteNote(sentence);
  }

  useEffect(() => {
    if (!request?.question) return undefined;
    run(request.question);
    return () => abortRef.current?.abort();
    // Re-ask only when a new observation request arrives.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [request]);

  function onSubmit(event) {
    event.preventDefault();
    run(draft);
  }

  const summary = selectionLine(selection, lang, copy);
  const busy = phase === 'loading' || cardPhase === 'loading';

  return (
    <section id="recommandation-technique" className="rag-panel" aria-labelledby="rag-title" data-assistant-panel="true">
      <div className="rag-heading">
        <BookOpen size={18} aria-hidden="true" />
        <div>
          <h2 id="rag-title">{copy.title}</h2>
          <p>{copy.intro}</p>
        </div>
      </div>

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
      {urlError && <p className="rag-error" role="alert">{urlError}</p>}

      {route === 'checking' && (
        <p className="rag-loading" role="status">{copy.checking}</p>
      )}
      {route === 'saved' && (
        <p className="rag-loading" role="status">{copy.ready}</p>
      )}
      {route === 'local' && routeNote && (
        <p className="rag-loading" role="status" data-assistant-route="local">{routeNote}</p>
      )}
      {route === 'down' && routeNote && (
        <p className="rag-error" role="status" data-assistant-error="true">{routeNote}</p>
      )}

      <div className="rag-transcript" data-assistant-transcript="live" aria-live="polite">
        {messages.length === 0 && phase !== 'loading' && (
          <p className="rag-empty">{route === 'local' ? copy.emptyLocal : copy.empty}</p>
        )}
        {messages.map((message) => (
          <article
            key={message.id}
            className={message.role === 'user' ? 'rag-msg rag-msg-user' : 'rag-msg rag-msg-assistant'}
            data-role={message.role}
          >
            <p className="rag-kicker">{message.role === 'user' ? copy.you : copy.answer}</p>
            {message.error ? (
              <p className="rag-error" role="alert" data-assistant-error="true">{message.error}</p>
            ) : (
              <p className="rag-answer" data-assistant-answer="true">{message.text}</p>
            )}
            {message.source && (
              <p className="rag-top-source" data-assistant-source="true">
                <span>{copy.topSource}</span>
                <strong title={message.source}>{sourceFileName(message.source)}</strong>
                {Number.isFinite(Number(message.score)) && (
                  <em>{copy.score} {Number(message.score).toFixed(4)}</em>
                )}
              </p>
            )}
          </article>
        ))}
      </div>

      <form className="rag-form" onSubmit={onSubmit}>
        <label htmlFor="rag-question">
          <span>{copy.questionLabel}</span>
          <textarea
            id="rag-question"
            value={draft}
            disabled={busy}
            placeholder={copy.placeholder}
            data-assistant-question="true"
            onChange={(event) => setDraft(event.target.value)}
          />
        </label>
        <div className="rag-controls">
          <button type="submit" className="btn btn-primary" disabled={busy || !draft.trim()}>
            {copy.submit}
          </button>
        </div>
      </form>
      {phase === 'loading' && <p className="rag-loading" role="status">{copy.loading}</p>}
      {messages.some((message) => message.role === 'assistant' && message.text) && (
        <p className="rag-disclaimer">{copy.disclaimer}</p>
      )}

      <div className="rag-selected" data-retained-observation="true">
        <p className="rag-kicker">{copy.selected}</p>
        <p data-retained-summary="true">{summary || copy.none}</p>
        <button
          type="button"
          className="btn btn-secondary"
          data-retained-ask="true"
          disabled={!selection || busy}
          onClick={askRetained}
        >
          {copy.askSelection}
        </button>
        {cardPhase === 'loading' && (
          <p className="rag-loading" role="status">{copy.loading}</p>
        )}
        {cardNote && (
          <p className="rag-error" role="alert" data-retained-note="true">{cardNote}</p>
        )}
        {cardResult?.answer && (
          <div data-retained-answer="true">
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
