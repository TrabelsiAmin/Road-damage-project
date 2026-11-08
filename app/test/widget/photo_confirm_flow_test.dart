import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:tariqmap/models/observation.dart';
import 'package:tariqmap/screens/photo_confirm_screen.dart';
import 'package:tariqmap/screens/result_screen.dart';
import 'package:tariqmap/services/detection_service.dart';
import 'package:tariqmap/services/observation_repository.dart';

class _CountingRunner implements DetectionAgentRunner {
  _CountingRunner({this.gate});

  final Completer<void>? gate;
  int calls = 0;

  @override
  String get agentName => 'road_damage';

  @override
  bool get isReady => true;

  @override
  bool get isMock => false;

  @override
  void dispose() {}

  @override
  Future<AgentResult> detect(File image) async {
    calls++;
    final gate = this.gate;
    if (gate != null) await gate.future;
    return const AgentResult(
      agent: 'road_damage',
      detections: [
        Detection(
          agent: 'road_damage',
          classCode: 'D00',
          confidence: 0.9,
          box: BoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
        ),
      ],
    );
  }
}

Future<void> _open({
  required WidgetTester tester,
  required ImageSource source,
  required MemoryObservationRepository repository,
  required _CountingRunner runner,
  required Future<File?> Function(ImageSource source) acquire,
  ImageProvider? previewFor,
  Uint8List? imageBytes,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () {
            runPhotoConfirmLoop(
              source: source,
              acquire: acquire,
              confirm: (file) =>
                  Navigator.of(context).push<PhotoConfirmOutcome>(
                MaterialPageRoute(
                  builder: (_) => PhotoConfirmScreen(
                    imageFile: file,
                    preview: previewFor,
                    imageBytes: imageBytes,
                    detectionService:
                        DetectionService.custom(runners: [runner]),
                    repository: repository,
                    actor: 'Municipality',
                  ),
                ),
              ),
            );
          },
          child: const Text('Take Photo'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Take Photo'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('camera and gallery both open the confirm preview',
      (tester) async {
    for (final source in [ImageSource.camera, ImageSource.gallery]) {
      final photo = File(
          '${Directory.systemTemp.path}/tariqmap_${source.name}_missing.jpg');
      if (photo.existsSync()) photo.deleteSync();
      final repo = MemoryObservationRepository();
      final runner = _CountingRunner();
      await _open(
        tester: tester,
        source: source,
        repository: repo,
        runner: runner,
        acquire: (asked) async {
          expect(asked, source);
          return photo;
        },
      );

      expect(find.text('Confirm Photo'), findsOneWidget);
      final preview = tester
          .widget<Image>(find.byKey(const ValueKey('photo-confirm-preview')));
      expect(preview.image, isA<FileImage>());
      expect((preview.image as FileImage).file.path, photo.path);
      expect(await repo.list(), isEmpty);
      expect(runner.calls, 0);
    }
  });

  testWidgets('retake does not save and asks the same source again',
      (tester) async {
    for (final source in [ImageSource.camera, ImageSource.gallery]) {
      final photo = File(
          '${Directory.systemTemp.path}/tariqmap_${source.name}_retake.jpg');
      if (photo.existsSync()) photo.deleteSync();
      final repo = MemoryObservationRepository();
      final runner = _CountingRunner();
      final asked = <ImageSource>[];
      await _open(
        tester: tester,
        source: source,
        repository: repo,
        runner: runner,
        acquire: (incoming) async {
          asked.add(incoming);
          return asked.length == 1 ? photo : null;
        },
      );

      await tester.tap(find.text('Retake'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Confirm Photo'), findsNothing);
      expect(await repo.list(), isEmpty);
      expect(runner.calls, 0);
      expect(asked, [source, source]);
    }
  });

  testWidgets('cancel before a file does not open confirm or save',
      (tester) async {
    for (final source in [ImageSource.camera, ImageSource.gallery]) {
      final repo = MemoryObservationRepository();
      final runner = _CountingRunner();
      await _open(
        tester: tester,
        source: source,
        repository: repo,
        runner: runner,
        acquire: (_) async => null,
      );
      expect(find.text('Confirm Photo'), findsNothing);
      expect(await repo.list(), isEmpty);
      expect(runner.calls, 0);
    }
  });

  testWidgets('analyse saves once and opens the result screen', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'),
      (call) async => switch (call.method) {
        'isLocationServiceEnabled' => false,
        _ => null,
      },
    );
    final bytes = img.encodePng(img.Image(width: 8, height: 8));
    final photo = File('/tmp/tariqmap_analyse_missing.png');
    if (photo.existsSync()) photo.deleteSync();
    final repo = MemoryObservationRepository();
    final gate = Completer<void>();
    final runner = _CountingRunner(gate: gate);
    await _open(
      tester: tester,
      source: ImageSource.gallery,
      repository: repo,
      runner: runner,
      imageBytes: bytes,
      acquire: (_) async => photo,
    );

    final preview = tester
        .widget<Image>(find.byKey(const ValueKey('photo-confirm-preview')));
    expect(preview.image, isA<FileImage>());
    expect((preview.image as FileImage).file.path, photo.path);

    await tester.tap(find.text('Analyse'));
    await tester.pump();
    expect(find.text('Analysing with AI…'), findsOneWidget);
    expect(find.text('Analyse'), findsNothing);
    expect(runner.calls, 1);
    expect(await repo.list(), isEmpty);

    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ResultScreen), findsOneWidget);
    expect(find.text('Analysis Results'), findsOneWidget);
    expect((await repo.list()).length, 1);
    expect(runner.calls, 1);
  });
}
