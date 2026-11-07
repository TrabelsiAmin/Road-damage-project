import 'package:flutter_test/flutter_test.dart';
import 'package:tariqmap/services/sync_plan.dart';

void main() {
  test('stable ids do not change across a retry', () {
    final first = stableDetectionId('obs-1', 0, 0);
    final second = stableDetectionId('obs-1', 0, 0);
    expect(second, first);
    expect(stableAgentRunId('obs-1', 0, 'road_damage'),
        '0b7e22ee-2f0d-5c02-89b3-b81c7ff0608a');
    expect(first, 'b22059ac-91f0-5481-a0f0-827e38a79359');
  });

  test('a retry inserts only ids that are not already stored', () {
    final rows = [
      {'id': 'keep'},
      {'id': 'missing'},
    ];
    final missing = rowsMissing(rows, {'keep'});
    expect(missing.map((row) => row['id']), ['missing']);
  });

  test('synced requires observation, children, and media', () {
    expect(
      syncMayComplete(
        observationReady: true,
        childrenReady: true,
        mediaReady: false,
        authOk: true,
        networkOk: true,
      ),
      isFalse,
    );
    expect(
      syncMayComplete(
        observationReady: true,
        childrenReady: false,
        mediaReady: true,
        authOk: true,
        networkOk: true,
      ),
      isFalse,
    );
    expect(
      syncMayComplete(
        observationReady: true,
        childrenReady: true,
        mediaReady: true,
        authOk: false,
        networkOk: true,
      ),
      isFalse,
    );
    expect(
      syncMayComplete(
        observationReady: true,
        childrenReady: true,
        mediaReady: true,
        authOk: true,
        networkOk: false,
      ),
      isFalse,
    );
    expect(
      syncMayComplete(
        observationReady: true,
        childrenReady: true,
        mediaReady: true,
        authOk: true,
        networkOk: true,
      ),
      isTrue,
    );
  });

  test('sync errors do not keep a JWT-shaped token', () {
    const leaked =
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoidGVzdCJ9.c2lnbmF0dXJl';
    expect(redactSecrets('failed $leaked'), isNot(contains('eyJ')));
  });
}
