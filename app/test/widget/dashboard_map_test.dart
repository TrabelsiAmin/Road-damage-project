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
        expect(find.text('Photo not shared publicly.'), findsOneWidget);
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

    testWidgets(
      'pin detail card shows public thumbnail through public-photos bucket when available',
      (tester) async {
        const obsId = 'public-obs-888';

        final initialObs = [
          {
            'id': obsId,
            'capture_id': 'cap-pub-888',
            'anomaly_type': 'D40',
            'priority_score': 75.0,
            'priority_label': 'CRITICAL',
            'status': 'unconfirmed',
            'created_at': '2026-10-15T09:00:00Z',
          }
        ];

        final initialLocs = [
          {
            'observation_id': obsId,
            'latitude': 36.8065,
            'longitude': 10.1815,
            'accuracy_meters': 2.0,
          }
        ];

        final initialDets = [
          {
            'observation_id': obsId,
            'class_code': 'D40',
            'confidence': 0.92,
            'box_x': 0.2,
            'box_y': 0.2,
            'box_w': 0.4,
            'box_h': 0.4,
          }
        ];

        final initialMedia = [
          {
            'observation_id': obsId,
            'bucket': 'public-photos',
            'storage_path': '$obsId/thumb-uuid.webp',
            'public_url': 'https://lendqcjihusqkmxansbl.supabase.co/storage/v1/object/public/public-photos/$obsId/thumb-uuid.webp',
            'media_type': 'thumbnail',
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
                  initialMediaFiles: initialMedia,
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
        await tester.pump(const Duration(milliseconds: 100));

        // Assert public thumbnail container and public preview badge are displayed
        expect(find.byKey(const ValueKey('public_thumbnail_container')), findsOneWidget);
        expect(find.text('Public preview (cropped to the damage)'), findsOneWidget);
        expect(find.text('Photo not public'), findsNothing);
      },
    );

    testWidgets(
      'observation with zero detections is shown as "No anomaly detected" and sheet title is "No Anomaly Detected"',
      (tester) async {
        const obsId = 'zero-det-obs-1';

        final initialObs = [
          {
            'id': obsId,
            'capture_id': 'cap-zero-1',
            'anomaly_type': null,
            'priority_score': 0.0,
            'priority_label': 'LOW',
            'status': 'unconfirmed',
            'created_at': '2026-10-15T10:00:00Z',
          }
        ];

        final initialLocs = [
          {
            'observation_id': obsId,
            'latitude': 36.8065,
            'longitude': 10.1815,
            'accuracy_meters': 5.0,
          }
        ];

        final initialDets = <Map<String, dynamic>>[]; // zero detections

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

        final pinFinder = find.byKey(const ValueKey('pin_36.8065_10.1815'));
        expect(pinFinder, findsOneWidget);

        // Tap Pin
        await tester.tap(pinFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Sheet title must NOT say "1 Anomaly Record"
        expect(find.text('No Anomaly Detected'), findsOneWidget);
        expect(find.text('1 Anomaly Record'), findsNothing);
        expect(find.text('1 Anomaly Records'), findsNothing);

        // Observation card must display "No anomaly detected" and NONE pill
        expect(find.text('No anomaly detected'), findsOneWidget);
        expect(find.text('NONE'), findsOneWidget);
        expect(find.text('None'), findsWidgets); // CONFIDENCE and PRIORITY should show None
      },
    );

    testWidgets(
      'mixed cluster with 1 anomaly and 1 zero-detection observation keeps zero-detection out of the count in sheet title',
      (tester) async {
        const obsWithDamage = 'obs-damage-1';
        const obsZeroDet = 'obs-zero-2';

        final initialObs = [
          {
            'id': obsWithDamage,
            'capture_id': 'cap-1',
            'anomaly_type': 'D40',
            'priority_score': 55.0,
            'priority_label': 'HIGH',
            'status': 'unconfirmed',
            'created_at': '2026-10-15T11:00:00Z',
          },
          {
            'id': obsZeroDet,
            'capture_id': 'cap-2',
            'anomaly_type': null,
            'priority_score': 0.0,
            'priority_label': 'LOW',
            'status': 'unconfirmed',
            'created_at': '2026-10-15T11:05:00Z',
          },
        ];

        // Same location so they cluster together
        final initialLocs = [
          {
            'observation_id': obsWithDamage,
            'latitude': 36.8065,
            'longitude': 10.1815,
            'accuracy_meters': 3.0,
          },
          {
            'observation_id': obsZeroDet,
            'latitude': 36.8065,
            'longitude': 10.1815,
            'accuracy_meters': 3.0,
          },
        ];

        final initialDets = [
          {
            'observation_id': obsWithDamage,
            'class_code': 'D40',
            'confidence': 0.72,
            'box_x': 0.1,
            'box_y': 0.1,
            'box_w': 0.2,
            'box_h': 0.2,
          },
          // obsZeroDet has no detections in initialDets
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

        final pinFinder = find.byKey(const ValueKey('pin_36.8065_10.1815'));
        expect(pinFinder, findsOneWidget);

        // Tap Pin
        await tester.tap(pinFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Sheet title must count only the 1 anomaly record, not 2
        expect(find.text('1 Anomaly Record'), findsOneWidget);
        expect(find.text('2 Anomaly Records'), findsNothing);

        // First card (with anomaly) is visible at the top
        expect(find.text('Pothole'), findsOneWidget);
        expect(find.text('D40'), findsOneWidget);

        // Scroll sheet ListView to bring the zero-detection observation card into view
        await tester.drag(find.byType(ListView), const Offset(0, -400));
        await tester.pumpAndSettle();

        expect(find.text('No anomaly detected'), findsOneWidget);
        expect(find.text('NONE'), findsOneWidget);
      },
    );
  });
}

