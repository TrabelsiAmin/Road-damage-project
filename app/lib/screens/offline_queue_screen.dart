import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../core/app_colors.dart';
import '../models/observation.dart';
import '../services/observation_repository.dart';
import 'result_screen.dart';

class OfflineQueueScreen extends StatefulWidget {
  const OfflineQueueScreen({
    super.key,
    required this.repository,
    required this.onSync,
  });

  final ObservationRepository     repository;
  final Future<void> Function()   onSync;

  @override
  State<OfflineQueueScreen> createState() => _OfflineQueueScreenState();
}

class _OfflineQueueScreenState extends State<OfflineQueueScreen>
    with SingleTickerProviderStateMixin {
  List<Observation> _all = [];
  bool _loading  = true;
  bool _syncing  = false;

  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final obs = await widget.repository.list();
    if (mounted) setState(() { _all = obs; _loading = false; });
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

  List<Observation> get _pending   => _all
      .where((o) => o.syncStatus == SyncStatus.pending ||
                    o.syncStatus == SyncStatus.uploading).toList();
  List<Observation> get _failed    => _all
      .where((o) => o.syncStatus == SyncStatus.failed ||
                    o.syncStatus == SyncStatus.needsReview).toList();
  List<Observation> get _synced    => _all
      .where((o) => o.syncStatus == SyncStatus.synced).toList();

  @override
  Widget build(BuildContext context) {
    final hasPendingOrFailed = _pending.isNotEmpty || _failed.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        elevation: 0,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Sync Queue',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            Text(
              '${_pending.length} pending · ${_failed.length} failed · ${_synced.length} synced',
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ],
        ),
        actions: [
          if (hasPendingOrFailed)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _syncing
                      ? AppColors.navyLight
                      : AppColors.teal,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _syncing ? null : _syncAll,
                icon: _syncing
                    ? const SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.cloud_upload_outlined, size: 16),
                label: Text(_syncing ? 'Syncing…' : 'Sync All',
                  style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ),
        ],
        bottom: _all.isEmpty ? null : TabBar(
          controller: _tab,
          indicatorColor: AppColors.tealGlow,
          indicatorWeight: 2,
          labelColor: AppColors.tealGlow,
          unselectedLabelColor: Colors.white54,
          labelStyle: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700),
          tabs: [
            Tab(text: 'Pending (${_pending.length})'),
            Tab(text: 'Failed (${_failed.length})'),
            Tab(text: 'Synced (${_synced.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.teal)))
          : _all.isEmpty
              ? _buildEmpty()
              : TabBarView(
                  controller: _tab,
                  children: [
                    _ObsList(observations: _pending, emptyMessage: 'All caught up!',
                      emptyIcon: Icons.cloud_done_rounded,
                      emptyColor: AppColors.syncDone),
                    _ObsList(observations: _failed, emptyMessage: 'No failed uploads.',
                      emptyIcon: Icons.check_circle_outline_rounded,
                      emptyColor: AppColors.syncDone),
                    _ObsList(observations: _synced, emptyMessage: 'Nothing synced yet.',
                      emptyIcon: Icons.cloud_outlined,
                      emptyColor: AppColors.textFaintOnDark),
                  ],
                ),
    );
  }

  Widget _buildEmpty() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            color: AppColors.teal.withAlpha(15),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.cloud_done_rounded,
            size: 36, color: AppColors.teal.withAlpha(180)),
        ),
        const SizedBox(height: 16),
        const Text('No observations yet',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 6),
        const Text('Captured observations will appear here.',
          style: TextStyle(color: Colors.black45)),
      ],
    ),
  );
}

// ── List ──────────────────────────────────────────────────────────────────────

class _ObsList extends StatelessWidget {
  const _ObsList({
    required this.observations,
    required this.emptyMessage,
    required this.emptyIcon,
    required this.emptyColor,
  });

  final List<Observation> observations;
  final String            emptyMessage;
  final IconData          emptyIcon;
  final Color             emptyColor;

  @override
  Widget build(BuildContext context) {
    if (observations.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(emptyIcon, size: 48, color: emptyColor.withAlpha(120)),
            const SizedBox(height: 12),
            Text(emptyMessage,
              style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 15, color: Colors.black54)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.teal,
      onRefresh: () async {},
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        itemCount: observations.length,
        itemBuilder: (_, i) => _ObsCard(obs: observations[i]),
      ),
    );
  }
}

// ── Obs card ──────────────────────────────────────────────────────────────────

class _ObsCard extends StatelessWidget {
  const _ObsCard({required this.obs});
  final Observation obs;

  Color get _statusColor => switch (obs.syncStatus) {
    SyncStatus.pending     => AppColors.syncPending,
    SyncStatus.uploading   => AppColors.tealLight,
    SyncStatus.synced      => AppColors.syncDone,
    SyncStatus.failed      => AppColors.syncFailed,
    SyncStatus.needsReview => AppColors.syncFailed,
  };

  String get _statusLabel => switch (obs.syncStatus) {
    SyncStatus.pending     => 'PENDING',
    SyncStatus.uploading   => 'UPLOADING',
    SyncStatus.synced      => 'SYNCED',
    SyncStatus.failed      => 'FAILED',
    SyncStatus.needsReview => 'NEEDS REVIEW',
  };

  IconData get _statusIcon => switch (obs.syncStatus) {
    SyncStatus.synced      => Icons.cloud_done_rounded,
    SyncStatus.uploading   => Icons.cloud_sync_rounded,
    SyncStatus.failed      => Icons.cloud_off_rounded,
    SyncStatus.needsReview => Icons.error_outline_rounded,
    _                      => Icons.cloud_upload_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final priorityColor = AppColors.forPriority(obs.priorityScore);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(6),
            blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ResultScreen(observation: obs))),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  // thumbnail
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 52, height: 52,
                      child: kIsWeb
                          ? Image.network(obs.imagePath, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _thumb())
                          : Image.file(File(obs.imagePath), fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _thumb()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: priorityColor.withAlpha(20),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${obs.priorityScore.toStringAsFixed(0)} · ${obs.priorityLabel}',
                              style: TextStyle(
                                color: priorityColor,
                                fontSize: 11, fontWeight: FontWeight.w700)),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: _statusColor.withAlpha(20),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: _statusColor.withAlpha(60), width: 1),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(_statusIcon, size: 10, color: _statusColor),
                              const SizedBox(width: 3),
                              Text(_statusLabel,
                                style: TextStyle(
                                  color: _statusColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700)),
                            ]),
                          ),
                        ]),
                        const SizedBox(height: 4),
                        Text(
                          '${obs.detections.length} anomaly${obs.detections.length == 1 ? '' : 's'} · ${obs.actor}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                        Text(
                          '${obs.latitude.toStringAsFixed(4)}, ${obs.longitude.toStringAsFixed(4)}  ·  '
                          '${DateFormat('dd MMM HH:mm').format(obs.createdAt.toLocal())}',
                          style: const TextStyle(
                            color: Colors.black38, fontSize: 11),
                          overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ]),
                if (obs.syncError != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.syncFailed.withAlpha(12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.syncFailed.withAlpha(40)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline,
                        size: 14, color: AppColors.syncFailed),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(obs.syncError!,
                          style: const TextStyle(
                            color: AppColors.syncFailed, fontSize: 11),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis)),
                    ]),
                  ),
                ],
                if (obs.anyMock) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.mockWarning.withAlpha(15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('⚠ DEMO MOCK INFERENCE',
                      style: TextStyle(
                        color: AppColors.mockWarning,
                        fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _thumb() => Container(
    color: AppColors.offWhite,
    child: const Icon(Icons.image_not_supported_outlined, color: Colors.black26));
}
