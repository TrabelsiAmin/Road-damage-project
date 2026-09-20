/// WP5 incident lifecycle constants.
///
/// This is the validated status machine. Persistence, SIG matching, and RAG
/// recommendations are PLANNED — this file does not invent a GIS product.
///
/// Validated chain:
///   DETECTED → ANALYZED → ASSIGNED → IN_PROGRESS → RESOLVED → ARCHIVED
enum IncidentStatus {
  detected,
  analyzed,
  assigned,
  inProgress,
  resolved,
  archived,
}

extension IncidentStatusCodec on IncidentStatus {
  String get wireName => switch (this) {
        IncidentStatus.detected => 'DETECTED',
        IncidentStatus.analyzed => 'ANALYZED',
        IncidentStatus.assigned => 'ASSIGNED',
        IncidentStatus.inProgress => 'IN_PROGRESS',
        IncidentStatus.resolved => 'RESOLVED',
        IncidentStatus.archived => 'ARCHIVED',
      };

  static IncidentStatus parse(String name) {
    final upper = name.toUpperCase();
    return IncidentStatus.values.firstWhere(
      (s) => s.wireName == upper,
      orElse: () => throw FormatException('Unknown incident status: $name'),
    );
  }
}

/// Forward-only incident transitions. No skips, no reverse without a new
/// observation. The responsible actor (peer institution) confirms each step.
class IncidentLifecycle {
  IncidentLifecycle._();

  static const order = <IncidentStatus>[
    IncidentStatus.detected,
    IncidentStatus.analyzed,
    IncidentStatus.assigned,
    IncidentStatus.inProgress,
    IncidentStatus.resolved,
    IncidentStatus.archived,
  ];

  static const allowedTransitions = <IncidentStatus, Set<IncidentStatus>>{
    IncidentStatus.detected: {IncidentStatus.analyzed},
    IncidentStatus.analyzed: {IncidentStatus.assigned},
    IncidentStatus.assigned: {IncidentStatus.inProgress},
    IncidentStatus.inProgress: {IncidentStatus.resolved},
    IncidentStatus.resolved: {IncidentStatus.archived},
    IncidentStatus.archived: {},
  };

  static bool canTransition(IncidentStatus from, IncidentStatus to) =>
      allowedTransitions[from]?.contains(to) ?? false;
}
