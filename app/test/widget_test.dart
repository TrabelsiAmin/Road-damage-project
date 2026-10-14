import 'package:flutter_test/flutter_test.dart';
import 'package:tariqmap/main.dart';
import 'package:tariqmap/screens/home_screen.dart';

void main() {
  testWidgets('TariqMap app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const TariqMapApp());
    expect(find.byType(TariqMapApp), findsOneWidget);
    expect(find.byType(HomeScreen), findsOneWidget);
  });
}
