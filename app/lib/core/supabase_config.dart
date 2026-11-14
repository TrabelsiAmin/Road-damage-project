/// TariqMap — Supabase project configuration.
///
/// IMPORTANT SECURITY NOTE:
/// - [anonKey] is the Supabase "anon/public" key. It is safe to embed in
///   client code; it is governed by Row Level Security (RLS) policies.
/// - The values below are the public project URL and the public anon key.
///   `--dart-define=SUPABASE_URL` and `--dart-define=SUPABASE_ANON_KEY`
///   override them. The literals stay so a local run without defines still
///   starts. Do not replace them with an empty string.
/// - No service-role key is stored in the Flutter app. The service-role
///   secret MUST remain server-side only (backend process environment)
///   and must NEVER appear in the Flutter app or in logs.
library tariqmap.supabase_config;

import 'dart:convert';

class SupabaseCfg {
  SupabaseCfg._();

  // ── Project credentials ────────────────────────────────────────────────────

  /// Supabase project URL. Override with --dart-define=SUPABASE_URL=...
  /// Falls back to the canonical public project URL if not provided.
  static const String _envUrl = String.fromEnvironment('SUPABASE_URL');

  /// Supabase anon / public key. Override with --dart-define=SUPABASE_ANON_KEY=...
  /// Falls back to the canonical public anon key if not provided.
  /// Governed by Supabase Row Level Security (RLS). This is not a service-role secret.
  static const String _envKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static const String _defaultUrl = 'https://lendqcjihusqkmxansbl.supabase.co';
  static const String _defaultKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxlbmRxY2ppaHVzcWtteGFuc2JsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAyODA3ODYsImV4cCI6MjEwNTg1Njc4Nn0.F1FS2HZNf7qEbTx14WBSAOHeCWTGsA5OMZghgw_YNNs';

  static String get url {
    final fromEnv = _envUrl.trim();
    if (fromEnv.isNotEmpty) return fromEnv;
    return _defaultUrl;
  }

  static String get anonKey {
    final fromEnv = _envKey.trim();
    if (fromEnv.isNotEmpty) return fromEnv;
    return _defaultKey;
  }

  /// Fails startup when the public config is empty or is a service-role key.
  /// The key value is not included in the error.
  static void assertPublicConfig() {
    final projectUrl = url.trim();
    final key = anonKey.trim();
    if (projectUrl.isEmpty || !projectUrl.startsWith('https://')) {
      throw StateError(
        'Supabase URL is missing. Pass --dart-define=SUPABASE_URL=https://...',
      );
    }
    if (key.isEmpty || key.length < 20) {
      throw StateError(
        'Supabase anon key is missing. Pass --dart-define=SUPABASE_ANON_KEY=... '
        'The value is not logged.',
      );
    }
    if (_jwtRole(key) == 'service_role') {
      throw StateError(
        'Refusing to start: the Flutter client must not use a service-role key.',
      );
    }
  }

  static String? _jwtRole(String token) {
    try {
      final parts = token.split('.');
      if (parts.length < 2) return null;
      var payload = parts[1];
      final pad = payload.length % 4;
      if (pad > 0) payload += '=' * (4 - pad);
      final json = utf8.decode(base64Url.decode(payload));
      final match = RegExp(r'"role"\s*:\s*"([^"]+)"').firstMatch(json);
      return match?.group(1);
    } catch (_) {
      return null;
    }
  }

  // ── Storage buckets ────────────────────────────────────────────────────────

  /// Bucket for captured still images (annotated JPEGs).
  static const String imagesBucket = 'observation-images';

  /// Bucket for public blurred thumbnails (max 300 KB, webp/jpeg only).
  static const String publicPhotosBucket = 'public-photos';

  // ── Database tables ────────────────────────────────────────────────────────

  static const String tableObservations = 'observations';
  static const String tableLocations = 'locations';
  static const String tableAgentRuns = 'agent_runs';
  static const String tableDetections = 'detections';
  static const String tableSyncReceipts = 'sync_receipts';
  static const String tableMediaFiles = 'media_files';
}
