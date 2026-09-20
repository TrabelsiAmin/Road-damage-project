import 'package:flutter_test/flutter_test.dart';
import 'package:tariqmap/core/constants.dart';
import 'package:tariqmap/models/incident.dart';
import 'package:tariqmap/models/observation.dart';
import 'package:tariqmap/services/observation_repository.dart';
import 'package:tariqmap/services/territorial_service.dart';

void main() {
  group('GPS-missing observations are kept', () {
    test('lat/lon 0 with detections still serializes and saves', () async {
      final repo = MemoryObservationRepository();
      final obs = Observation(
        id: 'obs-nogps',
        captureId: 'cap-nogps',
        imagePath: '/tmp/frame.jpg',
        createdAt: DateTime(2026, 9, 20),
        latitude: 0,
        longitude: 0,
        gpsAvailable: false,
        sourceVideoPath: '/tmp/clip.mp4',
        frameTimestampMs: 5000,
        actor: 'Municipality',
        agentResults: [
          AgentResult(
            agent: 'pavement',
            detections: [
              Detection(
                agent: 'pavement',
                classCode: 'D40',
                confidence: 0.91,
                box: const BoundingBox(x: 0.2, y: 0.3, width: 0.2, height: 0.2),
              ),
            ],
          ),
        ],
      );

      expect(obs.needsGpsEnrichment, isTrue);
      expect(obs.detections, hasLength(1));
      expect(obs.detections.first.classId, 'D40');
      expect(obs.toJson()['gpsAvailable'], isFalse);
      expect(obs.toJson()['sourceVideoPath'], '/tmp/clip.mp4');

      await repo.save(obs);
      final loaded = await repo.findById('obs-nogps');
      expect(loaded, isNotNull);
      expect(loaded!.gpsAvailable, isFalse);
      expect(loaded.latitude, 0);
      expect(loaded.longitude, 0);
      expect(loaded.detections, hasLength(1));
      expect(loaded.detections.first.classCode, 'D40');
      expect(loaded.sourceVideoPath, '/tmp/clip.mp4');
    });

    test('TerritorialService does not invent an owner without GPS', () {
      final match = TerritorialService().match(
        latitude: 0,
        longitude: 0,
        gpsAvailable: false,
      );
      expect(match.owner, 'unmatched');
      expect(match.matchQuality, 'none');
      expect(match.isMatched, isFalse);
    });

    test('TerritorialService does not rank actors by latitude', () {
      final north = TerritorialService().match(
        latitude: 37.0,
        longitude: 10.1,
        gpsAvailable: true,
      );
      final south = TerritorialService().match(
        latitude: 33.0,
        longitude: 10.1,
        gpsAvailable: true,
      );
      expect(north.owner, 'unmatched');
      expect(south.owner, 'unmatched');
      expect(north.owner, south.owner);
    });
  });

  group('Incident lifecycle', () {
    test('wire names match DETECTED…ARCHIVED', () {
      expect(
        IncidentLifecycle.order.map((s) => s.wireName).toList(),
        TariqMapConstants.incidentStatuses,
      );
    });

    test('forward transitions only', () {
      expect(
        IncidentLifecycle.canTransition(
          IncidentStatus.detected,
          IncidentStatus.analyzed,
        ),
        isTrue,
      );
      expect(
        IncidentLifecycle.canTransition(
          IncidentStatus.detected,
          IncidentStatus.assigned,
        ),
        isFalse,
      );
      expect(
        IncidentLifecycle.canTransition(
          IncidentStatus.archived,
          IncidentStatus.detected,
        ),
        isFalse,
      );
    });
  });

  group('WP2/WP3/WP4 split', () {
    test('D40 belongs only to WP3 pavement', () {
      expect(TariqMapConstants.agentFor('D40'), 'pavement');
      expect(TariqMapConstants.agentFor('D20'), 'pavement');
      expect(TariqMapConstants.priorityAgent, 'pavement');
      expect(TariqMapConstants.priorityClasses, ['D20', 'D40']);
      expect(TariqMapConstants.depthEstimationEnabled, isFalse);
    });

    test('three peer actors', () {
      expect(TariqMapConstants.actors, hasLength(3));
      expect(TariqMapConstants.actors, contains('Tunisia Autoroutes'));
      expect(TariqMapConstants.ragIsDecisionSupportOnly, isTrue);
    });
  });
}
