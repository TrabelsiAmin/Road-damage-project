import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tariqmap/screens/settings_screen.dart';
import 'package:tariqmap/services/sync_policy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('saved Wi-Fi-only and retention values are shown after reload',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      SyncSettings.wifiOnlyKey: false,
      SyncSettings.retentionDaysKey: 30,
    });

    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('30 days'), findsOneWidget);
    expect(find.textContaining('Wi-Fi is not required'), findsOneWidget);
    expect(find.textContaining('Pending, failed, and needs-review photos stay'),
        findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final stored = SyncSettings.fromPrefs(await SharedPreferences.getInstance());
    expect(stored.wifiOnly, isFalse);
    expect(stored.retentionDays, 30);
  });
}
