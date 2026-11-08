import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tariqmap/models/observation.dart';
import 'package:tariqmap/screens/home_screen.dart';
import 'package:tariqmap/screens/result_screen.dart';
import 'package:tariqmap/widgets/observation_photo.dart';

const _png = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void useImageClient(List<int> bytes, int statusCode) {
    debugNetworkImageHttpClientProvider = () => _Client(bytes, statusCode);
    addTearDown(() {
      debugNetworkImageHttpClientProvider = null;
      imageCache.clear();
      imageCache.clearLiveImages();
    });
  }

  Observation observation({
    required SyncStatus syncStatus,
    required MediaSyncStatus media,
    String? remote,
    String imagePath = '/tmp/tariqmap-phasee-missing.jpg',
  }) {
    return Observation(
      id: 'obs-photo',
      captureId: 'cap',
      imagePath: imagePath,
      remoteImageUrl: remote,
      createdAt: DateTime.utc(2026, 1, 1),
      latitude: 36.8,
      longitude: 10.1,
      actor: 'Municipality',
      syncStatus: syncStatus,
      mediaSyncStatus: media,
      agentResults: const [
        AgentResult(
          agent: 'road_damage',
          detections: [
            Detection(
              agent: 'road_damage',
              classCode: 'D00',
              confidence: 0.91,
              box: BoundingBox(x: 0.2, y: 0.3, width: 0.4, height: 0.2),
            ),
          ],
        ),
      ],
    );
  }

  testWidgets('history uses the remote photo after the local file is deleted',
      (tester) async {
    useImageClient(_png, 200);
    const url = 'https://cdn.example/original.webp';
    final obs = observation(
      syncStatus: SyncStatus.synced,
      media: MediaSyncStatus.uploaded,
      remote: url,
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HistoryObservationCard(
          observation: obs,
          index: 0,
          onTap: () {},
        ),
      ),
    ));
    await tester.pump();
    debugNetworkImageHttpClientProvider = null;

    expect(find.text('Remote photo'), findsOneWidget);
    expect(find.text('1 anomaly detected'), findsOneWidget);
    expect(find.text('Photo unavailable'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is NetworkImage &&
            (widget.image as NetworkImage).url == url,
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate((widget) => widget is Image && widget.image is FileImage),
      findsNothing,
    );
  });

  testWidgets('result keeps the class code when the remote photo is shown',
      (tester) async {
    useImageClient(_png, 200);
    const url = 'https://cdn.example/original.webp';
    await tester.pumpWidget(MaterialApp(
      home: ResultScreen(
        observation: observation(
          syncStatus: SyncStatus.synced,
          media: MediaSyncStatus.uploaded,
          remote: url,
        ),
      ),
    ));
    await tester.pump();
    debugNetworkImageHttpClientProvider = null;

    expect(find.text('Remote photo'), findsOneWidget);
    expect(find.text('D00'), findsOneWidget);
    expect(find.text('1 ANOMALY FOUND'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is NetworkImage &&
            (widget.image as NetworkImage).url == url,
      ),
      findsOneWidget,
    );
  });

  testWidgets('a failed remote image is labeled offline and is not the photo',
      (tester) async {
    useImageClient(const [1, 2, 3], 404);
    await tester.pumpWidget(MaterialApp(
      home: ResultScreen(
        observation: observation(
          syncStatus: SyncStatus.synced,
          media: MediaSyncStatus.uploaded,
          remote: 'https://cdn.example/missing.webp',
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    debugNetworkImageHttpClientProvider = null;

    expect(find.text('Photo offline'), findsOneWidget);
    expect(find.text('D00'), findsOneWidget);
    expect(find.text('Remote photo'), findsNothing);
  });

  testWidgets('a fully synced photo with no file and no url is unavailable',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ObservationPhoto(
          observation: observation(
            syncStatus: SyncStatus.synced,
            media: MediaSyncStatus.uploaded,
          ),
          localFileExists: false,
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('Photo unavailable'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('an incomplete upload does not pretend the photo is present',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ObservationPhoto(
          observation: observation(
            syncStatus: SyncStatus.needsReview,
            media: MediaSyncStatus.failed,
            remote: 'https://cdn.example/partial.webp',
          ),
          localFileExists: false,
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('Photo upload incomplete'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}

class _Client implements HttpClient {
  _Client(this.bytes, this.statusCode);
  final List<int> bytes;
  final int statusCode;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _Request(bytes, statusCode);
}

class _Request implements HttpClientRequest {
  _Request(this.bytes, this.statusCode);
  final List<int> bytes;
  final int statusCode;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  @override
  HttpHeaders get headers => _Headers();

  @override
  Future<HttpClientResponse> close() async => _Response(bytes, statusCode);
}

class _Response implements HttpClientResponse {
  _Response(this.bytes, this.statusCode);
  final List<int> bytes;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  @override
  final int statusCode;

  @override
  int get contentLength => bytes.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  HttpHeaders get headers => _Headers();

  @override
  Future<E> drain<E>([E? futureValue]) async => futureValue as E;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable([bytes]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

class _Headers implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
}
