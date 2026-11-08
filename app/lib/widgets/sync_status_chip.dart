import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../models/observation.dart';
import '../services/sync_plan.dart';

/// Short sync state for cards and the result screen.
///
/// The visible words are [queueStatusLabel], the same words as the offline
/// queue. The semantics label repeats that word and the queue sentence, so a
/// photo is not described as unsynced before metadata itself has synced.
class ObservationSyncChip extends StatelessWidget {
  const ObservationSyncChip({
    super.key,
    required this.observation,
    this.manualRetryInProgress = false,
  });

  final Observation observation;
  final bool manualRetryInProgress;

  @override
  Widget build(BuildContext context) {
    final state = queueSyncState(
      observation,
      manualRetryInProgress: manualRetryInProgress,
    );
    final label = queueStatusLabel(
      observation,
      manualRetryInProgress: manualRetryInProgress,
    );
    final uploading = observation.syncStatus == SyncStatus.uploading;
    final (icon, color) = switch (state) {
      QueueSyncState.notYetSynced => observation.syncStatus == SyncStatus.failed
          ? (Icons.cloud_off_rounded, AppColors.syncFailed)
          : uploading
              ? (Icons.cloud_sync_rounded, AppColors.tealLight)
              : (Icons.cloud_upload_outlined, AppColors.syncPending),
      QueueSyncState.metadataSyncedPhotoFailed => (
          Icons.cloud_off_rounded,
          AppColors.syncFailed,
        ),
      QueueSyncState.laterStepIncomplete => (
          Icons.cloud_off_rounded,
          AppColors.syncFailed,
        ),
      QueueSyncState.fullySynced => (
          Icons.cloud_done_rounded,
          AppColors.syncDone,
        ),
      QueueSyncState.manualReview => (
          Icons.error_outline_rounded,
          AppColors.syncFailed,
        ),
      QueueSyncState.manualRetryInProgress => (
          Icons.cloud_sync_rounded,
          AppColors.tealLight,
        ),
    };

    final detail = queueStatusMessage(
      observation,
      manualRetryInProgress: manualRetryInProgress,
    );
    return Semantics(
      container: true,
      label: '$label. $detail',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withAlpha(28),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withAlpha(90)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
