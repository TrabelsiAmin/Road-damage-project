import 'package:flutter/material.dart';

/// One home-strip state. The completed cloud is only [HomeSyncTone.synced].
enum HomeSyncTone { empty, review, failed, partial, pending, synced }

class HomeSyncSummary {
  const HomeSyncSummary({
    required this.pending,
    required this.failed,
    required this.partial,
    required this.review,
    required this.synced,
    required this.headline,
    required this.detail,
    required this.tone,
  });

  final int pending;
  final int failed;
  final int partial;
  final int review;
  final int synced;
  final String headline;
  final String detail;
  final HomeSyncTone tone;

  bool get offersSync => pending > 0 || failed > 0 || partial > 0;

  /// Failed rows can be retried when nothing is still waiting for a first send.
  String get syncButtonLabel =>
      failed > 0 && pending == 0 ? 'Retry' : 'Sync';

  IconData get icon => switch (tone) {
        HomeSyncTone.empty => Icons.cloud_outlined,
        HomeSyncTone.review => Icons.error_outline_rounded,
        HomeSyncTone.failed => Icons.cloud_off_rounded,
        HomeSyncTone.partial => Icons.cloud_sync_rounded,
        HomeSyncTone.pending => Icons.cloud_upload_outlined,
        HomeSyncTone.synced => Icons.cloud_done_rounded,
      };

  bool get showsCompletedCloud => icon == Icons.cloud_done_rounded;
}

String homeSyncCount(int count, String singular, String plural) =>
    '$count ${count == 1 ? singular : plural}';

/// Headline follows the most urgent category. [detail] keeps every category
/// that is present, so a review count cannot hide a failed count.
HomeSyncSummary summarizeHomeSync({
  required int pending,
  required int failed,
  required int partial,
  required int review,
  required int synced,
}) {
  final parts = <String>[
    if (review > 0) homeSyncCount(review, 'needs review', 'need review'),
    if (failed > 0) homeSyncCount(failed, 'failed', 'failed'),
    if (partial > 0) homeSyncCount(partial, 'partial', 'partial'),
    if (pending > 0) homeSyncCount(pending, 'pending', 'pending'),
    if (synced > 0) homeSyncCount(synced, 'fully synced', 'fully synced'),
  ];
  final total = pending + failed + partial + review + synced;
  final HomeSyncTone tone;
  final String headline;
  if (total == 0) {
    tone = HomeSyncTone.empty;
    headline = 'No observations yet';
  } else if (review > 0) {
    tone = HomeSyncTone.review;
    headline = homeSyncCount(review, 'needs review', 'need review');
  } else if (failed > 0) {
    tone = HomeSyncTone.failed;
    headline = homeSyncCount(failed, 'failed to sync', 'failed to sync');
  } else if (partial > 0) {
    tone = HomeSyncTone.partial;
    headline = homeSyncCount(partial, 'partially synced', 'partially synced');
  } else if (pending > 0) {
    tone = HomeSyncTone.pending;
    headline = homeSyncCount(pending, 'pending sync', 'pending sync');
  } else {
    tone = HomeSyncTone.synced;
    headline = 'All observations synced';
  }
  return HomeSyncSummary(
    pending: pending,
    failed: failed,
    partial: partial,
    review: review,
    synced: synced,
    headline: headline,
    detail: total == 0 ? 'Nothing is waiting to sync.' : parts.join(' · '),
    tone: tone,
  );
}
