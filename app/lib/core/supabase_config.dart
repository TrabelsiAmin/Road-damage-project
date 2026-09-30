/// TariqMap — Supabase project configuration.
///
/// IMPORTANT SECURITY NOTE:
/// - [anonKey] is the Supabase "anon/public" key. It is safe to embed in
///   client code; it is governed by Row Level Security (RLS) policies.
/// - The service-role secret (sb_secret_…) MUST remain server-side only
///   (backend/.env) and must NEVER appear in the Flutter app.
library tariqmap.supabase_config;

class SupabaseCfg {
  SupabaseCfg._();

  // ── Project credentials ────────────────────────────────────────────────────

  /// Supabase project URL.
  static const String url = 'https://lendqcjihusqkmxansbl.supabase.co';

  /// Supabase anon / public key (safe for client bundles).
  /// Obtain from: Supabase Dashboard → Settings → API → anon public.
  /// This is NOT the service-role secret.
  /// IMPORTANT: Replace the placeholder below with your real anon key.
  static const String anonKey =
      "sb_secret_gDI-QKrVOnOXIOcww19Xwg_7ARgROX2";


  // ── Storage buckets ────────────────────────────────────────────────────────

  /// Bucket for captured still images (annotated JPEGs).
  static const String imagesBucket = 'observation-images';

  /// Bucket for recorded live-stream video clips.
  static const String videosBucket = 'live-session-videos';

  // ── Database tables ────────────────────────────────────────────────────────

  static const String tableObservations = 'observations';
  static const String tableLocations    = 'locations';
  static const String tableAgentRuns    = 'agent_runs';
  static const String tableDetections   = 'detections';
  static const String tableSyncReceipts = 'sync_receipts';
  static const String tableMediaFiles   = 'media_files';
  static const String tableLiveSessions = 'live_sessions';
}

