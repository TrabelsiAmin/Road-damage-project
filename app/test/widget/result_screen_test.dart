import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tariqmap/models/observation.dart';
import 'package:tariqmap/screens/result_screen.dart';

void main() {
  testWidgets('ResultScreen shows correct analysis details', (WidgetTester tester) async {
    final observation = Observation(
      id: 'test_obs_1',
      captureId: 'test_cap_1',
      imagePath: 'test.jpg',
      createdAt: DateTime.now(),
      latitude: 36.8065,
      longitude: 10.1815,
      actor: 'Test User',
      agentResults: [
        const AgentResult(
          agent: 'mock_agent',
          isMock: true,
          detections: [
            Detection(
              agent: 'mock_agent',
              classCode: 'D00',
              confidence: 0.95,
              box: BoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
            )
          ],
        )
      ],
    );

    await tester.pumpWidget(MaterialApp(
      home: ResultScreen(observation: observation),
    ));

    expect(find.text('Analysis Results'), findsOneWidget);
    expect(find.text('Test'), findsOneWidget);
    expect(find.text('DEMO MOCK INFERENCE'), findsOneWidget);
    expect(find.text('Detected'), findsOneWidget);
  });
}
