# TariqMap Product and Engineering Specification

## Hackathon thesis

TariqMap turns a road image into an accountable territorial action without requiring a network connection at the inspection site. Its differentiator is not only object detection. It is the complete chain: **capture → explainable multi-agent inference → geolocation → responsible institution → prioritized incident → synchronized action history**.

## Personas and views

| Actor | Operational question | Primary screens |
|---|---|---|
| Municipality | Which local problems must be treated first? | Local map, priority queue, incident detail, intervention history |
| Ministry of Equipment | Where are network-level patterns and hotspots? | National map, comparative analytics, exports, coordination |
| Tunisia Autoroutes | Which highway problems require rapid intervention? | Live-ready alert queue, precise location, route/segment status |

The actor is an institution. The operator is a person using an institutional workspace. The three institutional actors are peers in the platform; the Ministry’s wider geographic scope does not imply UI hierarchy. RAG, when introduced, is decision support only — the actor decides.

## Core user journeys

### Inspection journey

The operator chooses an actor context, starts an inspection, grants location permission, captures or imports an image, and receives independent results from the three agents. The app displays the annotated image, confidence, classes, model version, and GPS quality. The operator may correct the responsible territory, add a note, or mark the observation for review. The observation is committed locally before any upload is attempted.

### Incident journey

A reviewable observation becomes an incident only after the operator confirms the suggested severity and owner. The incident has a stable identifier, audit history, status, priority, responsible actor, road and segment, evidence image, and optional intervention assignment.

Validated status chain (WP5): `DETECTED → ANALYZED → ASSIGNED → IN_PROGRESS → RESOLVED → ARCHIVED`.

Constants live in `app/lib/models/incident.dart` and `backend/lifecycle.py`. Persistence, dashboards, SIG matching, and RAG recommendations are **PLANNED** — Week 1 was specification-only.

### Synchronization journey

A background sync queue uploads observations idempotently. Network failure, expired authentication, conflict, and server validation errors have separate states. The queue uses exponential backoff with jitter, preserves local evidence, and never duplicates an incident when a retry occurs.

## Explainability and trust

Each box must display its originating agent and confidence. The app must show when a result is partial because an agent failed. Confidence is not severity. Priority is a triage score derived from class weight, confidence, recurrence, road importance, and evidence quality. The final operational decision remains with the responsible actor.

## Non-functional targets

| Area | Target for demo | Production direction |
|---|---:|---|
| Cold-start inference | under 2.5 seconds on a mid-range Android phone | device benchmark matrix and delegate selection |
| Offline capture | 100 observations without data loss | encrypted local database and disk quota policy |
| Agent isolation | one failure does not block others | crash-safe worker boundary and telemetry |
| Sync | retryable and idempotent | resumable upload and conflict resolution |
| Privacy | no public image URL by default | short-lived signed URLs, retention policy |
| Accessibility | readable contrast and large tap targets | WCAG-style mobile review and Arabic/French localization |

## Definition of done

The hackathon build is credible when it can demonstrate a real image, a real model bundle **or** a clearly labeled fallback, GPS metadata **or** a kept observation when GPS is missing, independent agent status, an explainable priority, offline persistence, and a retryable sync queue. Territorial ownership, incident lifecycle UI, and RAG are specified, not production.
