import 'package:flutter_test/flutter_test.dart';
import 'package:tariqmap/core/supabase_config.dart';
import 'package:tariqmap/data/remote/supabase_service.dart';

void main() {
  group('SupabaseCfg', () {
    test('provides valid default url and anon key without dart-define', () {
      expect(SupabaseCfg.url, isNotEmpty);
      expect(SupabaseCfg.url, startsWith('https://'));
      expect(SupabaseCfg.anonKey, isNotEmpty);
      expect(SupabaseCfg.anonKey.length, greaterThanOrEqualTo(20));
    });

    test('assertPublicConfig succeeds with default config', () {
      expect(() => SupabaseCfg.assertPublicConfig(), returnsNormally);
    });

    test('SupabaseService has initial state and safe offline methods', () async {
      expect(SupabaseService.isInitialized, isFalse);
      final anomalies = await SupabaseService.instance.fetchNearbyAnomalies(
        latitude: 36.8,
        longitude: 10.1,
      );
      expect(anomalies, isEmpty);

      final img = await SupabaseService.instance.downloadObservationImage(
        observationId: 'test-id',
      );
      expect(img, isNull);
    });
  });
}

