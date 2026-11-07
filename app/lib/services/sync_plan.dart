import 'package:uuid/uuid.dart';

/// Stable child ids for one local observation.
///
/// The same strings are used by the Python backend planner. A retry inserts
/// a row only when that id is absent. Existing rows are not deleted.
const _uuid = Uuid();

String stableAgentRunId(String observationId, int index, String agent) =>
    _uuid.v5(Namespace.url.value, '$observationId:agent:$index:$agent');

String stableDetectionId(String observationId, int agentIndex, int detectionIndex) =>
    _uuid.v5(Namespace.url.value, '$observationId:det:$agentIndex:$detectionIndex');

List<Map<String, dynamic>> rowsMissing(
  List<Map<String, dynamic>> rows,
  Set<String> existingIds,
) {
  return [
    for (final row in rows)
      if (!existingIds.contains(row['id']?.toString())) row,
  ];
}

/// Synced only when every required step finished.
/// A failed media upload, an auth error, or a dropped network stays unsynced.
/// Local rows are never deleted here.
bool syncMayComplete({
  required bool observationReady,
  required bool childrenReady,
  required bool mediaReady,
  required bool authOk,
  required bool networkOk,
}) {
  return observationReady && childrenReady && mediaReady && authOk && networkOk;
}

/// Strip JWT-shaped text before it is logged or stored on a sync error.
String redactSecrets(String text) {
  return text.replaceAll(
    RegExp(r'eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+'),
    '[redacted]',
  );
}
