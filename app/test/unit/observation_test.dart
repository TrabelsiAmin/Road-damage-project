import 'package:flutter_test/flutter_test.dart';
import 'package:tariqmap/models/observation.dart';
import 'package:tariqmap/core/constants.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Priority score
  // ---------------------------------------------------------------------------

  group('Observation.priorityScore', () {
    AgentResult _result(String code, double conf) => AgentResult(
      agent: 'test',
      detections: [
        Detection(
          agent: 'test',
          classCode: code,
          confidence: conf,
          box: const BoundingBox(x: 0.1, y: 0.1, width: 0.3, height: 0.3),
        ),
      ],
    );

    Observation _obs(List<AgentResult> results) => Observation(
      id: 'test-id',
      captureId: 'cap-id',
      imagePath: '/tmp/test.jpg',
      createdAt: DateTime(2026, 9, 1),
      latitude: 36.8,
      longitude: 10.2,
      actor: 'Municipality',
      agentResults: results,
    );

    test('empty detections → priorityScore = 0', () {
      final obs = _obs([AgentResult(agent: 'test', detections: const [])]);
      expect(obs.priorityScore, equals(0.0));
    });

    test('single D40 (pothole) at 100% confidence → high score', () {
      final obs = _obs([_result('D40', 1.0)]);
      // weight 1.0 * conf 1.0 / 1 * 100 = 100
      expect(obs.priorityScore, closeTo(100.0, 0.1));
    });

    test('single D60 (faded lane) at 50% confidence → low score', () {
      final obs = _obs([_result('D60', 0.5)]);
      // weight 0.5 * conf 0.5 / 1 * 100 = 25
      expect(obs.priorityScore, closeTo(25.0, 0.1));
    });

    test('priorityScore is clamped to [0..100]', () {
      final obs = _obs([_result('D40', 1.0), _result('D40', 1.0), _result('D40', 1.0)]);
      expect(obs.priorityScore, lessThanOrEqualTo(100.0));
      expect(obs.priorityScore, greaterThanOrEqualTo(0.0));
    });

    test('priorityLabel: CRITICAL for score >= 70', () {
      final obs = _obs([_result('D40', 1.0)]);
      expect(obs.priorityLabel, equals('CRITICAL'));
    });

    test('priorityLabel: LOW for score < 20', () {
      final obs = _obs([_result('D60', 0.1)]);
      expect(obs.priorityLabel, equals('LOW'));
    });
  });

  // ---------------------------------------------------------------------------
  // Observation.failedAgents
  // ---------------------------------------------------------------------------

  group('Observation.failedAgents', () {
    test('no errors → failedAgents = 0', () {
      final obs = Observation(
        id: 'x', captureId: 'y', imagePath: '/p', createdAt: DateTime.now(),
        latitude: 0, longitude: 0, actor: 'A',
        agentResults: [
          AgentResult(agent: 'cracks', detections: const []),
          AgentResult(agent: 'pavement', detections: const []),
        ],
      );
      expect(obs.failedAgents, equals(0));
    });

    test('one error → failedAgents = 1', () {
      final obs = Observation(
        id: 'x', captureId: 'y', imagePath: '/p', createdAt: DateTime.now(),
        latitude: 0, longitude: 0, actor: 'A',
        agentResults: [
          AgentResult(agent: 'cracks', detections: const [], error: 'load failed'),
          AgentResult(agent: 'pavement', detections: const []),
        ],
      );
      expect(obs.failedAgents, equals(1));
    });
  });

  // ---------------------------------------------------------------------------
  // Observation.anyMock
  // ---------------------------------------------------------------------------

  group('Observation.anyMock', () {
    test('all real → anyMock = false', () {
      final obs = Observation(
        id: 'x', captureId: 'y', imagePath: '/p', createdAt: DateTime.now(),
        latitude: 0, longitude: 0, actor: 'A',
        agentResults: [
          AgentResult(agent: 'cracks', detections: const [], isMock: false),
        ],
      );
      expect(obs.anyMock, isFalse);
    });

    test('one mock → anyMock = true', () {
      final obs = Observation(
        id: 'x', captureId: 'y', imagePath: '/p', createdAt: DateTime.now(),
        latitude: 0, longitude: 0, actor: 'A',
        agentResults: [
          AgentResult(agent: 'cracks', detections: const [], isMock: true),
          AgentResult(agent: 'pavement', detections: const [], isMock: false),
        ],
      );
      expect(obs.anyMock, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // TariqMapConstants
  // ---------------------------------------------------------------------------

  group('TariqMapConstants', () {
    test('all D-codes have a label', () {
      for (final code in TariqMapConstants.allCodes) {
        expect(TariqMapConstants.labels.containsKey(code), isTrue,
            reason: '$code has no label');
      }
    });

    test('agent classes are disjoint', () {
      final seen = <String>{};
      for (final entry in TariqMapConstants.agentClasses.entries) {
        for (final code in entry.value) {
          expect(seen, isNot(contains(code)),
              reason: '$code appears in multiple agents');
          seen.add(code);
        }
      }
    });

    test('all severity weights are in (0, 1]', () {
      for (final entry in TariqMapConstants.severityWeights.entries) {
        expect(entry.value, greaterThan(0),
            reason: '${entry.key} weight is non-positive');
        expect(entry.value, lessThanOrEqualTo(1.0),
            reason: '${entry.key} weight > 1.0');
      }
    });

    test('agentFor returns correct agent', () {
      expect(TariqMapConstants.agentFor('D40'), equals('pavement'));
      expect(TariqMapConstants.agentFor('D00'), equals('cracks'));
      expect(TariqMapConstants.agentFor('D60'), equals('surface'));
    });

    test('three agents stay disjoint and WP3 is priority', () {
      expect(TariqMapConstants.agentClasses.keys.toSet(),
          {'cracks', 'pavement', 'surface'});
      expect(TariqMapConstants.priorityAgent, 'pavement');
      expect(TariqMapConstants.depthEstimationEnabled, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // JSON serialisation round-trip
  // ---------------------------------------------------------------------------

  group('Observation.toJson', () {
    test('toJson includes all required fields', () {
      final obs = Observation(
        id: 'obs-1',
        captureId: 'cap-1',
        imagePath: '/data/img.jpg',
        createdAt: DateTime(2026, 9, 1, 12, 0, 0).toUtc(),
        latitude: 36.8065,
        longitude: 10.1815,
        actor: 'Municipality',
        agentResults: [
          AgentResult(
            agent: 'pavement',
            detections: [
              Detection(
                agent: 'pavement',
                classCode: 'D40',
                confidence: 0.88,
                box: const BoundingBox(x: 0.2, y: 0.3, width: 0.4, height: 0.3),
              ),
            ],
            isMock: true,
          ),
        ],
      );

      final json = obs.toJson();
      expect(json['id'], equals('obs-1'));
      expect(json['latitude'], closeTo(36.8065, 1e-6));
      expect(json['gpsAvailable'], isTrue);
      expect(json['priorityScore'], isNotNull);
      expect(json['priorityLabel'], isNotNull);
      expect(json['agentResults'], hasLength(1));
    });
  });
}
