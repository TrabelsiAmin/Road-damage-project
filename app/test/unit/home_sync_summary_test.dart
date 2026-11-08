import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tariqmap/services/home_sync_summary.dart';

void main() {
  test('pending only uses the upload icon and singular or plural grammar', () {
    final one = summarizeHomeSync(
      pending: 1, failed: 0, partial: 0, review: 0, synced: 0,
    );
    expect(one.headline, '1 pending sync');
    expect(one.detail, '1 pending');
    expect(one.tone, HomeSyncTone.pending);
    expect(one.icon, Icons.cloud_upload_outlined);
    expect(one.showsCompletedCloud, isFalse);
    expect(one.offersSync, isTrue);
    expect(one.syncButtonLabel, 'Sync');

    final many = summarizeHomeSync(
      pending: 3, failed: 0, partial: 0, review: 0, synced: 0,
    );
    expect(many.headline, '3 pending sync');
    expect(many.detail, '3 pending');
  });

  test('failed only uses the failed icon and keeps the failed count visible', () {
    final one = summarizeHomeSync(
      pending: 0, failed: 1, partial: 0, review: 0, synced: 0,
    );
    expect(one.headline, '1 failed to sync');
    expect(one.detail, '1 failed');
    expect(one.icon, Icons.cloud_off_rounded);
    expect(one.showsCompletedCloud, isFalse);
    expect(one.offersSync, isTrue);
    expect(one.syncButtonLabel, 'Retry');

    final many = summarizeHomeSync(
      pending: 0, failed: 2, partial: 0, review: 0, synced: 0,
    );
    expect(many.headline, '2 failed to sync');
    expect(many.detail, '2 failed');
  });

  test('partial only does not use the completed cloud icon', () {
    final one = summarizeHomeSync(
      pending: 0, failed: 0, partial: 1, review: 0, synced: 0,
    );
    expect(one.headline, '1 partially synced');
    expect(one.detail, '1 partial');
    expect(one.tone, HomeSyncTone.partial);
    expect(one.icon, isNot(Icons.cloud_done_rounded));
    expect(one.showsCompletedCloud, isFalse);
    expect(one.offersSync, isTrue);
    expect(one.syncButtonLabel, 'Sync');

    final many = summarizeHomeSync(
      pending: 0, failed: 0, partial: 4, review: 0, synced: 0,
    );
    expect(many.headline, '4 partially synced');
    expect(many.detail, '4 partial');
  });

  test('needs review only does not use the completed cloud icon', () {
    final one = summarizeHomeSync(
      pending: 0, failed: 0, partial: 0, review: 1, synced: 0,
    );
    expect(one.headline, '1 needs review');
    expect(one.detail, '1 needs review');
    expect(one.tone, HomeSyncTone.review);
    expect(one.icon, Icons.error_outline_rounded);
    expect(one.showsCompletedCloud, isFalse);
    expect(one.offersSync, isFalse);

    final many = summarizeHomeSync(
      pending: 0, failed: 0, partial: 0, review: 2, synced: 0,
    );
    expect(many.headline, '2 need review');
    expect(many.detail, '2 need review');
    expect(many.showsCompletedCloud, isFalse);
  });

  test('mixed states keep failed visible beside review', () {
    final mixed = summarizeHomeSync(
      pending: 2, failed: 3, partial: 1, review: 1, synced: 4,
    );
    expect(mixed.headline, '1 needs review');
    expect(mixed.detail, contains('1 needs review'));
    expect(mixed.detail, contains('3 failed'));
    expect(mixed.detail, contains('1 partial'));
    expect(mixed.detail, contains('2 pending'));
    expect(mixed.detail, contains('4 fully synced'));
    expect(mixed.tone, HomeSyncTone.review);
    expect(mixed.showsCompletedCloud, isFalse);
    expect(mixed.offersSync, isTrue);
    expect(mixed.syncButtonLabel, 'Sync');

    final reviewAndFailed = summarizeHomeSync(
      pending: 0, failed: 2, partial: 0, review: 2, synced: 0,
    );
    expect(reviewAndFailed.headline, '2 need review');
    expect(reviewAndFailed.detail, '2 need review · 2 failed');
    expect(reviewAndFailed.syncButtonLabel, 'Retry');
    expect(reviewAndFailed.showsCompletedCloud, isFalse);
  });

  test('fully synced only uses the completed cloud icon', () {
    final one = summarizeHomeSync(
      pending: 0, failed: 0, partial: 0, review: 0, synced: 1,
    );
    expect(one.headline, 'All observations synced');
    expect(one.detail, '1 fully synced');
    expect(one.tone, HomeSyncTone.synced);
    expect(one.icon, Icons.cloud_done_rounded);
    expect(one.showsCompletedCloud, isTrue);
    expect(one.offersSync, isFalse);

    final many = summarizeHomeSync(
      pending: 0, failed: 0, partial: 0, review: 0, synced: 5,
    );
    expect(many.headline, 'All observations synced');
    expect(many.detail, '5 fully synced');
    expect(many.icon, Icons.cloud_done_rounded);
  });

  test('an empty list does not claim that everything is synced', () {
    final empty = summarizeHomeSync(
      pending: 0, failed: 0, partial: 0, review: 0, synced: 0,
    );
    expect(empty.headline, 'No observations yet');
    expect(empty.detail, 'Nothing is waiting to sync.');
    expect(empty.headline, isNot(contains('All observations synced')));
    expect(empty.detail, isNot(contains('fully synced')));
    expect(empty.tone, HomeSyncTone.empty);
    expect(empty.icon, Icons.cloud_outlined);
    expect(empty.showsCompletedCloud, isFalse);
    expect(empty.offersSync, isFalse);
  });
}
