import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../models/observation.dart';
import '../services/observation_repository.dart';
import 'result_screen.dart';

/// Shows all observations organised by sync status.
///
/// Each card shows: thumbnail, priority, detections, GPS, sync status.
/// Retry button appears for [SyncStatus.failed] items.
class OfflineQueueScreen extends StatefulWidget {
  const OfflineQueueScreen({
    super.key,
    required this.repository,
    required this.onSync,
  });

  final ObservationRepository repository;

  /// Callback invoked when the user taps "Sync All". The caller decides
  /// whether connectivity is available.
  final Future<void> Function() onSync;

  @override
  State<OfflineQueueScreen> createState() => _OfflineQueueScreenState();
}

class _OfflineQueueScreenState extends State<OfflineQueueScreen> {
  List<Observation> _all = [];
  bool _loading = true;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final observations = await widget.repository.list();
    if (mounted) setState(() { _all = observations; _loading = false; });
  }

  Future<void> _syncAll() async {
    setState(() => _syncing = true);
    try {
      await widget.onSync();
      await _load();
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending   = _all.where((o) => o.syncStatus == SyncStatus.pending).toList();
    final uploading = _all.where((o) => o.syncStatus == SyncStatus.uploading).toList();
    final failed    = _all.where((o) => o.syncStatus == SyncStatus.failed || o.syncStatus == SyncStatus.needsReview).toList();
    final synced    = _all.where((o) => o.syncStatus == SyncStatus.synced).toList();

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Offline Queue', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text('${pending.length} pending · ${failed.length} failed · ${synced.length} synced',
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ],
        ),
        actions: [
          if (pending.isNotEmpty || failed.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                onPressed: _syncing ? null : _syncAll,
                icon: _syncing
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.cloud_upload_outlined, size: 18),
                label: Text(_syncing ? 'Syncing…' : 'Sync All'),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _all.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (uploading.isNotEmpty) ...[
                        _SectionHeader('Uploading', Icons.cloud_sync_outlined, Colors.blue, uploading.length),
                        ...uploading.map((o) => _ObsCard(obs: o, repo: widget.repository, onRefresh: _load)),
                        const SizedBox(height: 16),
                      ],
                      if (pending.isNotEmpty) ...[
                        _SectionHeader('Pending', Icons.cloud_upload_outlined, AppColors.syncPending, pending.length),
                        ...pending.map((o) => _ObsCard(obs: o, repo: widget.repository, onRefresh: _load)),
                        const SizedBox(height: 16),
                      ],
                      if (failed.isNotEmpty) ...[
                        _SectionHeader('Failed / Needs Review', Icons.error_outline, AppColors.syncFailed, failed.length),
                        ...failed.map((o) => _ObsCard(obs: o, repo: widget.repository, onRefresh: _load)),
                        const SizedBox(height: 16),
                      ],
                      if (synced.isNotEmpty) ...[
                        _SectionHeader('Synced', Icons.cloud_done_outlined, AppColors.syncDone, synced.length),
                        ...synced.map((o) => _ObsCard(obs: o, repo: widget.repository, onRefresh: _load)),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _buildEmpty() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle_outline, size: 64, color: AppColors.teal.withAlpha(120)),
        const SizedBox(height: 16),
        const Text('No observations yet.', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 4),
        const Text('Captured observations will appear here.', style: TextStyle(color: Colors.black45)),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Section header
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, this.icon, this.color, this.count);
  final String title;
  final IconData icon;
  final Color color;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 6),
      Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
      const SizedBox(width: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        decoration: BoxDecoration(
          color: color.withAlpha(30), borderRadius: BorderRadius.circular(8)),
        child: Text('$count', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11)),
      ),
    ]),
  );
}

// ---------------------------------------------------------------------------
// Observation card
// ---------------------------------------------------------------------------

class _ObsCard extends StatelessWidget {
  const _ObsCard({required this.obs, required this.repo, required this.onRefresh});
  final Observation obs;
  final ObservationRepository repo;
  final Future<void> Function() onRefresh;

  Color get _statusColor => switch (obs.syncStatus) {
    SyncStatus.pending     => AppColors.syncPending,
    SyncStatus.uploading   => Colors.blue,
    SyncStatus.synced      => AppColors.syncDone,
    SyncStatus.failed      => AppColors.syncFailed,
    SyncStatus.needsReview => AppColors.syncFailed,
  };

  @override
  Widget build(BuildContext context) {
    final priorityColor = AppColors.forPriority(obs.priorityScore);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0,
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => ResultScreen(observation: obs)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(width: 8, height: 8,
                    decoration: BoxDecoration(color: priorityColor, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text('${obs.priorityScore.toStringAsFixed(0)}/100 · ${obs.priorityLabel}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _statusColor.withAlpha(25),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _statusColor.withAlpha(80)),
                  ),
                  child: Text(obs.syncStatus.name.toUpperCase(),
                      style: TextStyle(color: _statusColor, fontWeight: FontWeight.bold, fontSize: 10)),
                ),
              ]),
              const SizedBox(height: 6),
              Text(
                '${obs.detections.length} detection${obs.detections.length == 1 ? '' : 's'}  ·  '
                '${obs.actor}  ·  ${obs.latitude.toStringAsFixed(4)}, ${obs.longitude.toStringAsFixed(4)}',
                style: const TextStyle(color: Colors.black45, fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
              if (obs.syncError != null) ...[
                const SizedBox(height: 4),
                Text('Error: ${obs.syncError}',
                    style: const TextStyle(color: AppColors.syncFailed, fontSize: 11),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
              if (obs.anyMock) ...[
                const SizedBox(height: 4),
                const Text('⚠ DEMO MOCK INFERENCE',
                    style: TextStyle(color: AppColors.mockWarning, fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
