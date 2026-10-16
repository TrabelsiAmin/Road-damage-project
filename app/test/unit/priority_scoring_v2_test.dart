import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tariqmap/models/observation.dart';
import 'package:tariqmap/utils/priority_scoring.dart';

void main() {
  group('Priority Scoring v2 - Core Requirements', () {
    test('Empty detections returns score 0 and LOW label', () {
      final res = calculatePriorityScoreV2([]);
      expect(res.score, equals(0.0));
      expect(res.label, equals('LOW'));
    });

    test('Detections below 0.25 confidence are ignored', () {
      final res = calculatePriorityScoreV2([
        const Detection(
          agent: 'test',
          classCode: 'D40',
          confidence: 0.24,
          box: BoundingBox(x: 0.1, y: 0.1, width: 0.3, height: 0.3),
        ),
        const Detection(
          agent: 'test',
          classCode: 'D20',
          confidence: 0.15,
          box: BoundingBox(x: 0.2, y: 0.2, width: 0.4, height: 0.4),
        ),
      ]);
      expect(res.score, equals(0.0));
      expect(res.label, equals('LOW'));
    });

    test('A single D40 at 0.41 is not HIGH (the pothole model is weak)', () {
      final res = calculatePriorityScoreV2([
        const Detection(
          agent: 'test',
          classCode: 'D40',
          confidence: 0.41,
          box: BoundingBox(x: 0.1, y: 0.1, width: 0.35, height: 0.35),
        ),
      ]);
      expect(res.score, lessThanOrEqualTo(PriorityScoringConfig.highThreshold));
      expect(res.label, isNot(equals('HIGH')));
      expect(res.label, equals('MEDIUM'));
    });

    test('1 pothole at 0.9 beats 9 faint cracks at 0.3', () {
      // 1 pothole at 0.9
      final potholeRes = calculatePriorityScoreV2([
        const Detection(
          agent: 'test',
          classCode: 'D40',
          confidence: 0.90,
          box: BoundingBox(x: 0.1, y: 0.1, width: 0.35, height: 0.35),
        ),
      ]);

      // 9 faint cracks at 0.3
      final faintCracksRes = calculatePriorityScoreV2(
        List.generate(
          9,
          (i) => Detection(
            agent: 'test',
            classCode: i.isEven ? 'D10' : 'D00',
            confidence: 0.30,
            box: const BoundingBox(x: 0.1, y: 0.1, width: 0.1, height: 0.1),
          ),
        ),
      );

      expect(potholeRes.score, greaterThan(faintCracksRes.score));
      expect(potholeRes.score, equals(90.0));
      expect(potholeRes.label, equals('HIGH'));
      expect(faintCracksRes.score, lessThan(PriorityScoringConfig.lowThreshold));
      expect(faintCracksRes.label, equals('LOW'));
    });

    test('Score is monotonic in confidence', () {
      final confidences = [0.26, 0.35, 0.45, 0.55, 0.70, 0.85, 0.98];
      double previousScore = -1.0;

      for (final conf in confidences) {
        final res = calculatePriorityScoreV2([
          Detection(
            agent: 'test',
            classCode: 'D20',
            confidence: conf,
            box: const BoundingBox(x: 0.1, y: 0.1, width: 0.4, height: 0.4),
          ),
        ]);
        expect(res.score, greaterThanOrEqualTo(previousScore),
            reason: 'Score at confidence $conf (${res.score}) should be >= score at previous conf ($previousScore)');
        previousScore = res.score;
      }
    });

    test('Observation.priorityScore and priorityLabel match calculatePriorityScoreV2', () {
      final obs = Observation(
        id: 'test-obs',
        captureId: 'test-cap',
        imagePath: '/tmp/test.jpg',
        createdAt: DateTime.now(),
        latitude: 36.8,
        longitude: 10.2,
        actor: 'Municipality',
        agentResults: [
          const AgentResult(
            agent: 'road_damage',
            detections: [
              Detection(
                agent: 'road_damage',
                classCode: 'D40',
                confidence: 0.90,
                box: BoundingBox(x: 0.1, y: 0.1, width: 0.35, height: 0.35),
              ),
            ],
          ),
        ],
      );

      expect(obs.priorityScore, equals(90.0));
      expect(obs.priorityLabel, equals('HIGH'));
    });
  });

  group('Priority Scoring v2 - Shared Golden Test Vectors', () {
    test('Matches shared/priority_golden.json vector values exactly', () {
      final file = File('../shared/priority_golden.json').existsSync()
          ? File('../shared/priority_golden.json')
          : File('shared/priority_golden.json');

      expect(file.existsSync(), isTrue, reason: 'shared/priority_golden.json must exist');

      final jsonContent = jsonDecode(file.readAsStringSync()) as List<dynamic>;

      for (final entry in jsonContent) {
        final description = entry['description'] as String;
        final rawDets = entry['detections'] as List<dynamic>;
        final expectedScore = (entry['expectedScore'] as num).toDouble();
        final expectedLabel = entry['expectedLabel'] as String;

        final detections = rawDets.map((d) {
          final boxMap = (d['box'] ?? {}) as Map<String, dynamic>;
          return Detection(
            agent: 'test',
            classCode: d['classCode'] as String,
            confidence: (d['confidence'] as num).toDouble(),
            box: BoundingBox(
              x: (boxMap['x'] as num?)?.toDouble() ?? 0.0,
              y: (boxMap['y'] as num?)?.toDouble() ?? 0.0,
              width: (boxMap['width'] as num?)?.toDouble() ?? 0.0,
              height: (boxMap['height'] as num?)?.toDouble() ?? 0.0,
            ),
          );
        }).toList();

        final result = calculatePriorityScoreV2(detections);

        expect(
          result.score,
          closeTo(expectedScore, 0.01),
          reason: 'Failed vector "$description": expected $expectedScore, got ${result.score}',
        );
        expect(
          result.label,
          equals(expectedLabel),
          reason: 'Failed label for "$description": expected $expectedLabel, got ${result.label}',
        );
      }
    });
  });
}
