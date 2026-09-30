"""WP5 lifecycle and actor constants.

These are specification-aligned constants for the mock backend.
They do not implement GIS matching, incident persistence, or RAG.

Incident status chain (validated conception):
    DETECTED → ANALYZED → ASSIGNED → IN_PROGRESS → RESOLVED → ARCHIVED

Actors are peers. There is no platform hierarchy among
Municipalité, Ministère de l'Équipement, and Tunisie Autoroutes.

RAG, when introduced, is decision-support only — the actor decides.
"""
from __future__ import annotations

INCIDENT_STATUSES: tuple[str, ...] = (
    "DETECTED",
    "ANALYZED",
    "ASSIGNED",
    "IN_PROGRESS",
    "RESOLVED",
    "ARCHIVED",
)

INCIDENT_TRANSITIONS: dict[str, tuple[str, ...]] = {
    "DETECTED": ("ANALYZED",),
    "ANALYZED": ("ASSIGNED",),
    "ASSIGNED": ("IN_PROGRESS",),
    "IN_PROGRESS": ("RESOLVED",),
    "RESOLVED": ("ARCHIVED",),
    "ARCHIVED": (),
}

ACTORS: tuple[str, ...] = (
    "Municipality",
    "Ministry of Equipment",
    "Tunisia Autoroutes",
)

# French names from the validated conception — same three peers.
ACTORS_FR: tuple[str, ...] = (
    "Municipalité",
    "Ministère de l'Équipement",
    "Tunisie Autoroutes",
)

RAG_ROLE = "decision_support_only"


def can_transition(current: str, nxt: str) -> bool:
    return nxt in INCIDENT_TRANSITIONS.get(current, ())
