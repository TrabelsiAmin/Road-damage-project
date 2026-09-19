import 'package:flutter_test/flutter_test.dart';

import 'package:tariqmap/main.dart';


void main() {
  testWidgets('TariqMap app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const TariqMapApp());
    expect(find.text('TariqMap'), findsOneWidget);
  });
}
