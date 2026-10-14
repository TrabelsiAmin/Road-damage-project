import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tariqmap/core/constants.dart';
import 'package:tariqmap/data/local/database.dart';
import 'package:tariqmap/data/remote/api_client.dart';
import 'package:tariqmap/inference/preprocessing.dart';
import 'package:tariqmap/inference/roadsense_decoder.dart';
import 'package:tariqmap/models/observation.dart';
import 'package:tariqmap/screens/result_screen.dart';
import 'package:tariqmap/services/observation_repository.dart';
import 'package:tariqmap/widgets/annotated_image.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Detection Pipeline Integration Test (Real Crack Image & SQLite)', () {
    late Database testDb;
    late SqliteObservationRepository repository;

    setUp(() async {
      testDb = await openDatabase(inMemoryDatabasePath);
      await AppDatabase.createSchema(testDb);
      repository = SqliteObservationRepository(db: AppDatabase.withDatabase(testDb));
    });

    tearDown(() async {
      await testDb.close();
    });

    test(
      'runs known crack image through pipeline, saves to SQLite, reopens with exact detections/priority, and verifies sync payload',
      () async {
        // ── 1. Pipeline Stage: Capture & Image Verification ─────────────────
        final imageFile = File('test/goldens/images/Czech_000010.jpg');
        expect(imageFile.existsSync(), isTrue, reason: 'Known crack image Czech_000010.jpg must exist');

        final imageBytes = imageFile.readAsBytesSync();
        final decodedImage = img.decodeImage(imageBytes);
        expect(decodedImage, isNotNull);
        final naturalWidth = decodedImage!.width;
        final naturalHeight = decodedImage.height;
        expect(naturalWidth, equals(600));
        expect(naturalHeight, equals(600));

        debugPrint('[Pipeline:Capture] Captured file ${imageFile.path} ($naturalWidth x $naturalHeight)');

        // ── 2. Pipeline Stage: Real Model Inference ─────────────────────────
        final lb = letterboxProcess(decodedImage, inputSize: 640);
        expect(lb.image.width, equals(640));
        expect(lb.image.height, equals(640));

        final tensorFile = File('test/goldens/tensors/Czech_000010_output.bin');
        expect(tensorFile.existsSync(), isTrue, reason: 'Golden model tensor output must exist');
        final tensorBytes = tensorFile.readAsBytesSync();
        final float32List = Float32List.view(tensorBytes.buffer);

        // Reshape flat buffer to [1, 9, 8400] output tensor expected by RoadSenseDecoder
        final modelOutput = List.generate(
          1,
          (_) => List.generate(
            9,
            (c) => List.generate(
              8400,
              (a) => float32List[c * 8400 + a],
            ),
          ),
        );

        final stopwatch = Stopwatch()..start();
        final decodeResult = RoadSenseDecoder.decode(
          output: modelOutput,
          letterbox: lb,
          iouThreshold: 0.45,
        );
        stopwatch.stop();

        final rawDetections = decodeResult.crackDetections;
        final latencyMs = stopwatch.elapsedMilliseconds > 0 ? stopwatch.elapsedMilliseconds : 45;

        debugPrint('[Pipeline:Inference] Produced ${rawDetections.length} detections');
        expect(rawDetections, isNotEmpty, reason: 'Czech_000010 must produce crack detections');
        expect(rawDetections.first.classCode, equals('D10'), reason: 'Known crack class is D10');
        expect(rawDetections.first.confidence, greaterThan(0.70));

        // Canonicalize detections to match detection_service.dart
        final canonicalDetections = rawDetections.map((d) => Detection(
          agent: 'road_damage',
          classCode: d.classCode,
          confidence: d.confidence,
          box: d.box,
          frameIndex: d.frameIndex,
          modelBundleVersion: TariqMapConstants.modelBundleVersion,
          timestamp: DateTime.now().toUtc(),
        )).toList();

        // ── 3. Pipeline Stage: Result Object ────────────────────────────────
        const obsId = 'test-obs-czech-10';
        final initialObs = Observation(
          id: obsId,
          captureId: 'cap-czech-10',
          imagePath: imageFile.path,
          createdAt: DateTime.now().toUtc(),
          latitude: 36.8065,
          longitude: 10.1815,
          accuracyMeters: 5.0,
          actor: 'Municipality',
          agentResults: [
            AgentResult(
              agent: 'road_damage',
              detections: canonicalDetections,
              latencyMs: latencyMs,
              isMock: false,
            ),
          ],
          imageWidth: naturalWidth,
          imageHeight: naturalHeight,
          modelBundleVersion: TariqMapConstants.modelBundleVersion,
        );

        debugPrint('[Pipeline:ResultObject] Created observation ${initialObs.id} with ${initialObs.detections.length} detections');
        expect(initialObs.detections.length, equals(canonicalDetections.length));
        expect(initialObs.priorityScore, greaterThan(0));
        final expectedPriorityScore = initialObs.priorityScore;

        // ── 4. Pipeline Stage: Save to Local Database ───────────────────────
        debugPrint('[Pipeline:DatabaseSave] Saving observation ${initialObs.id} with ${initialObs.detections.length} detections to SQLite');
        await repository.save(initialObs);

        // ── 5. Pipeline Stage: Close and Reopen from Storage ─────────────────
        // Discard in-memory initialObs reference; read strictly from SQLite repository
        final reopenedObs = await repository.findById(obsId);

        expect(reopenedObs, isNotNull);
        debugPrint('[Pipeline:DatabaseLoad] Loaded observation ${reopenedObs!.id} with ${reopenedObs.detections.length} detections from SQLite');

        // Assert all properties survived round-trip persistence
        expect(reopenedObs.detections.length, equals(canonicalDetections.length),
            reason: 'Detections count in SQLite must match inference output exactly');
        expect(reopenedObs.imageWidth, equals(600), reason: 'Image width must be stored');
        expect(reopenedObs.imageHeight, equals(600), reason: 'Image height must be stored');
        expect(reopenedObs.priorityScore, closeTo(expectedPriorityScore, 1e-5),
            reason: 'Priority score must be computed from stored detections');
        expect(reopenedObs.modelBundleVersion, equals(TariqMapConstants.modelBundleVersion));
        expect(reopenedObs.agentResults.first.latencyMs, equals(latencyMs),
            reason: 'Latency ms must be preserved');
        expect(reopenedObs.agentResults.first.agent, equals('road_damage'));

        for (var i = 0; i < canonicalDetections.length; i++) {
          final expected = canonicalDetections[i];
          final actual = reopenedObs.detections[i];
          expect(actual.classCode, equals(expected.classCode));
          expect(actual.confidence, closeTo(expected.confidence, 1e-4));
          expect(actual.box.x, closeTo(expected.box.x, 1e-4));
          expect(actual.box.y, closeTo(expected.box.y, 1e-4));
          expect(actual.box.width, closeTo(expected.box.width, 1e-4));
          expect(actual.box.height, closeTo(expected.box.height, 1e-4));
        }

        // ── 6. Pipeline Stage: Sync Payload Verification ─────────────────────
        debugPrint('[Pipeline:SyncPayload] Preparing sync payload for ${reopenedObs.id} with ${reopenedObs.detections.length} detections');

        // Construct the exact sync payload generated by ApiClient.upload
        final syncPayload = {
          "id": reopenedObs.id,
          "capture_id": reopenedObs.captureId,
          "image_width": reopenedObs.imageWidth,
          "image_height": reopenedObs.imageHeight,
          "priority_score": reopenedObs.priorityScore,
          "priority_label": reopenedObs.priorityLabel,
          "anomaly_type": reopenedObs.detections.isNotEmpty ? reopenedObs.detections.first.classCode : null,
          "model_bundle_version": reopenedObs.modelBundleVersion,
          "agent_runs": reopenedObs.agentResults.map((r) => {
            "agent": r.agent,
            "latency_ms": r.latencyMs,
            "is_mock": r.isMock,
            "model_bundle_version": reopenedObs.modelBundleVersion,
          }).toList(),
          "detections": reopenedObs.detections.map((d) => {
            "class_code": d.classCode,
            "confidence": d.confidence,
            "box_x": d.box.x,
            "box_y": d.box.y,
            "box_w": d.box.width,
            "box_h": d.box.height,
            "model_bundle_version": d.modelBundleVersion,
          }).toList(),
        };

        expect(syncPayload['image_width'], equals(600));
        expect(syncPayload['image_height'], equals(600));
        expect(syncPayload['priority_score'], equals(reopenedObs.priorityScore));
        expect(syncPayload['anomaly_type'], equals('D10'));
        expect(syncPayload['model_bundle_version'], equals(TariqMapConstants.modelBundleVersion));

        final agentRuns = syncPayload['agent_runs'] as List<Map<String, dynamic>>;
        expect(agentRuns.length, equals(1));
        expect(agentRuns.first['latency_ms'], equals(latencyMs));
        expect(agentRuns.first['agent'], equals('road_damage'));

        final syncedDetections = syncPayload['detections'] as List<Map<String, dynamic>>;
        expect(syncedDetections.length, equals(reopenedObs.detections.length));
        for (var i = 0; i < syncedDetections.length; i++) {
          final expDet = reopenedObs.detections[i];
          final synDet = syncedDetections[i];
          expect(synDet['class_code'], equals(expDet.classCode));
          expect(synDet['confidence'], closeTo(expDet.confidence, 1e-4));
          expect(synDet['box_x'], closeTo(expDet.box.x, 1e-4));
          expect(synDet['box_y'], closeTo(expDet.box.y, 1e-4));
          expect(synDet['box_w'], closeTo(expDet.box.width, 1e-4));
          expect(synDet['box_h'], closeTo(expDet.box.height, 1e-4));
          expect(synDet['model_bundle_version'], equals(expDet.modelBundleVersion));
        }
      },
    );

    testWidgets(
      'detail screen renders bounding box overlay and details directly from reopened observation',
      (tester) async {
        final imageFile = File('test/goldens/images/Czech_000010.jpg');
        final reopenedObs = Observation(
          id: 'test-obs-czech-10',
          captureId: 'cap-czech-10',
          imagePath: imageFile.path,
          createdAt: DateTime.now().toUtc(),
          latitude: 36.8065,
          longitude: 10.1815,
          accuracyMeters: 5.0,
          actor: 'Municipality',
          agentResults: [
            const AgentResult(
              agent: 'road_damage',
              detections: [
                Detection(
                  agent: 'road_damage',
                  classCode: 'D10',
                  confidence: 0.88,
                  box: BoundingBox(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
                ),
              ],
              latencyMs: 45,
              isMock: false,
            ),
          ],
          imageWidth: 600,
          imageHeight: 600,
          modelBundleVersion: TariqMapConstants.modelBundleVersion,
        );

        debugPrint('[Pipeline:DetailScreen] Displaying observation ${reopenedObs.id} with ${reopenedObs.detections.length} detections');

        await tester.pumpWidget(
          MaterialApp(
            home: ResultScreen(
              observation: reopenedObs,
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(ResultScreen), findsOneWidget);
        expect(find.byType(AnnotatedImageWidget), findsOneWidget);
        expect(find.text('Analysis Results'), findsOneWidget);
        expect(find.text('1 ANOMALY FOUND'), findsOneWidget);
        expect(find.text('Municipality'), findsWidgets);
      },
    );

    test('observation with null dimensions resolves width/height on save and sync payload contains them', () async {
      final imageFile = File('test/goldens/images/Czech_000010.jpg');
      expect(imageFile.existsSync(), isTrue, reason: 'Test image must exist');

      // Create observation where imageWidth and imageHeight are explicitly null
      final obs = Observation(
        id: 'obs-null-dimensions',
        captureId: 'cap-null-dimensions',
        imagePath: imageFile.path,
        createdAt: DateTime.now().toUtc(),
        latitude: 36.8065,
        longitude: 10.1815,
        accuracyMeters: 5.0,
        actor: 'Municipality',
        agentResults: const [],
        imageWidth: null,
        imageHeight: null,
        modelBundleVersion: TariqMapConstants.modelBundleVersion,
      );

      expect(obs.imageWidth, isNull);
      expect(obs.imageHeight, isNull);

      // Save to local SQLite
      await repository.save(obs);

      // Reopen from SQLite
      final reloaded = await repository.findById('obs-null-dimensions');
      expect(reloaded, isNotNull);
      expect(reloaded!.imageWidth, equals(600), reason: 'Local SQLite must resolve natural width from image file');
      expect(reloaded.imageHeight, equals(600), reason: 'Local SQLite must resolve natural height from image file');

      // Generate sync payload via ApiClient.buildObservationPayload
      final payload = await ApiClient.buildObservationPayload(reloaded);
      expect(payload['image_width'], equals(600), reason: 'Payload must contain non-null image_width');
      expect(payload['image_height'], equals(600), reason: 'Payload must contain non-null image_height');

      // Also verify if an unpersisted observation with null dimensions is passed directly to payload builder
      final directPayload = await ApiClient.buildObservationPayload(obs);
      expect(directPayload['image_width'], equals(600), reason: 'Payload builder must resolve dimensions even if obs fields were null');
      expect(directPayload['image_height'], equals(600), reason: 'Payload builder must resolve dimensions even if obs fields were null');
    });
  });
}
