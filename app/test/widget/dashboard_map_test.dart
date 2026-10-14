import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tariqmap/models/observation.dart';
import 'package:tariqmap/services/observation_repository.dart';
import 'package:tariqmap/widgets/annotated_image.dart';
import 'package:tariqmap/widgets/dashboard_map.dart';

void main() {
  group('DashboardMap Pin Tap & Detail Card Tests', () {
    late MemoryObservationRepository memoryRepo;

    setUp(() {
      memoryRepo = MemoryObservationRepository();
    });

    testWidgets(
      'pin tap opens the detail card with all anon-readable telemetry without an image, and shows neutral placeholder for remote device',
      (tester) async {
        const obsId = 'remote-obs-49f723a4';

        final initialObs = [
          {
            'id': obsId,
            'capture_id': 'cap-1',
            'anomaly_type': 'D40',
            'priority_score': 41.4,
            'priority_label': 'HIGH',
            'status': 'unconfirmed',
            'created_at': '2026-10-14T14:30:00Z',
          }
        ];

        final initialLocs = [
          {
            'observation_id': obsId,
            'latitude': 36.8065,
            'longitude': 10.1815,
            'accuracy_meters': 4.5,
          }
        ];

        final initialDets = [
          {
            'observation_id': obsId,
            'class_code': 'D40',
            'confidence': 0.65,
            'box_x': 0.1,
            'box_y': 0.2,
            'box_w': 0.3,
            'box_h': 0.4,
          }
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 400,
                child: DashboardMap(
                  repository: memoryRepo,
                  initialObservations: initialObs,
                  initialLocations: initialLocs,
                  initialDetections: initialDets,
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // 1. Assert Pin marker is rendered
        final pinFinder = find.byKey(const ValueKey('pin_36.8065_10.1815'));
        expect(pinFinder, findsOneWidget, reason: 'Pin marker must be rendered on the map');

        // 2. Tap Pin
        await tester.tap(pinFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // 3. Assert detail card is open and shows all anon-readable fields
        expect(find.text('1 Anomaly Record'), findsOneWidget);
        expect(find.text('D40'), findsOneWidget);
        expect(find.text('Pothole'), findsOneWidget);
        expect(find.text('CONFIDENCE'), findsOneWidget);
        expect(find.text('65%'), findsOneWidget);
        expect(find.text('PRIORITY'), findsOneWidget);
        expect(find.text('41 (HIGH)'), findsOneWidget);
        expect(find.text('STATUS'), findsOneWidget);
        expect(find.text('UNCONFIRMED'), findsWidgets);
        expect(find.text('POSITION'), findsOneWidget);
        expect(find.textContaining('36.8065, 10.1815'), findsOneWidget);

        // 4. Assert neutral placeholder is shown (not from this device, no local image)
        expect(find.text('Photo not public'), findsOneWidget);
        expect(
          find.text(
              'Municipal privacy policy restricts raw imagery to authorized road authorities. Anomaly telemetry and AI bounding boxes are public.'),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.lock_outline), findsOneWidget);
        expect(find.byType(AnnotatedImageWidget), findsNothing);
      },
    );

    testWidgets(
      'local image is used when observation exists on device, rendering AnnotatedImageWidget with bounding boxes',
      (tester) async {
        final realImageFile = File('test/goldens/images/Czech_000010.jpg');
        expect(realImageFile.existsSync(), isTrue, reason: 'Test fixture image must exist');

        const localObsId = 'local-device-obs-1';

        // Save observation into local SQLite/Memory repository
        final localObservation = Observation(
          id: localObsId,
          captureId: 'cap-local-1',
          imagePath: realImageFile.path,
          createdAt: DateTime.parse('2026-10-14T14:30:00Z'),
          latitude: 36.8065,
          longitude: 10.1815,
          accuracyMeters: 3.0,
          actor: 'Municipality',
          agentResults: const [
            AgentResult(
              agent: 'road_damage',
              detections: [
                Detection(
                  agent: 'road_damage',
                  classCode: 'D10',
                  confidence: 0.88,
                  box: BoundingBox(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
                ),
              ],
            ),
          ],
          imageWidth: 600,
          imageHeight: 600,
        );
        await memoryRepo.save(localObservation);

        final initialObs = [
          {
            'id': localObsId,
            'capture_id': 'cap-local-1',
            'anomaly_type': 'D10',
            'priority_score': 62.0,
            'priority_label': 'HIGH',
            'status': 'unconfirmed',
            'created_at': '2026-10-14T14:30:00Z',
          }
        ];

        final initialLocs = [
          {
            'observation_id': localObsId,
            'latitude': 36.8065,
            'longitude': 10.1815,
            'accuracy_meters': 3.0,
          }
        ];

        final initialDets = [
          {
            'observation_id': localObsId,
            'class_code': 'D10',
            'confidence': 0.88,
            'box_x': 0.1,
            'box_y': 0.2,
            'box_w': 0.3,
            'box_h': 0.4,
          }
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 400,
                child: DashboardMap(
                  repository: memoryRepo,
                  initialObservations: initialObs,
                  initialLocations: initialLocs,
                  initialDetections: initialDets,
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Find and tap Pin
        final pinFinder = find.byKey(const ValueKey('pin_36.8065_10.1815'));
        expect(pinFinder, findsOneWidget);
        await tester.tap(pinFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Assert AnnotatedImageWidget is rendered for local capture
        expect(find.byType(AnnotatedImageWidget), findsOneWidget,
            reason: 'Local capture must display AnnotatedImageWidget');
        expect(find.text('Local capture (on device)'), findsOneWidget);
        expect(find.text('Photo not public'), findsNothing,
            reason: 'Local capture must NOT display placeholder');

        // Assert all anon-readable telemetry fields
        expect(find.text('D10'), findsOneWidget);
        expect(find.text('Transverse Crack'), findsOneWidget);
        expect(find.text('88%'), findsOneWidget);
        expect(find.text('62 (HIGH)'), findsOneWidget);
      },
    );
  });
}
