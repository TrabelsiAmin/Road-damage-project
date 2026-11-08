import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../core/app_colors.dart';
import '../models/observation.dart';
import '../services/observation_repository.dart';
import '../services/sync_plan.dart';
import '../widgets/observation_photo.dart';
import 'result_screen.dart';

class OfflineQueueScreen extends StatefulWidget {
  const OfflineQueueScreen({
    super.key,
    required this.repository,
    required this.onSync,
    this.onManualRetry,
  });

  final ObservationRepository repository;
  final Future<SyncResult> Function({SyncCancelToken? cancelToken}) onSync;

  /// One explicit retry of a needsReview row. Automatic sync does not call this.
  final Future<SyncResult> Function(String observationId,
      {SyncCancelToken? cancelToken})? onManualRetry;

  @override
  State<OfflineQueueScreen> createState() => _OfflineQueueScreenState();
}

class _OfflineQueueScreenState extends State<OfflineQueueScreen>
    with SingleTickerProviderStateMixin {
  List<Observation> _all = [];
  bool _loading = true;
  bool _syncing = false;
  String? _manualRetryId;
  SyncCancelToken? _cancelToken;
  String? _statusBanner;
  bool _statusBlocked = false;
  String? _loadError;

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
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final obs = await widget.repository.list();
      if (mounted) {
        setState(() {
          _all = obs;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[Queue] Load error: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = 'Could not load the local queue.';
        });
      }
    }
  }

  Future<void> _syncAll() async {
    final token = SyncCancelToken();
    setState(() {
      _syncing = true;
      _cancelToken = token;
      _statusBanner = null;
      _statusBlocked = false;
    });
    try {
      final result = await widget.onSync(cancelToken: token);
      await _load();
      if (mounted) {
        setState(() {
          _statusBanner = result.message;
          _statusBlocked = result.blocked;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: result.cancelled || result.blocked
                ? Colors.orange.shade800
                : AppColors.teal,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      debugPrint('[Queue] Sync error: $e');
      if (mounted) {
        setState(() => _statusBanner = 'Sync failed.');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sync failed.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _syncing = false;
          _cancelToken = null;
        });
      }
    }
  }

  void _cancelSync() {
    _cancelToken?.cancel();
  }

  Future<void> _retryNeedsReview(Observation obs) async {
    final retry = widget.onManualRetry;
    if (retry == null || _syncing || _manualRetryId != null) return;
    setState(() => _manualRetryId = obs.id);
    try {
      final result = await retry(obs.id);
      await _load();
      if (!mounted) return;
      setState(() {
        _statusBanner = result.message;
        _statusBlocked = result.blocked;
      });
    } catch (e) {
      debugPrint('[Queue] Manual retry error: $e');
      await _load();
      if (!mounted) return;
      setState(() => _statusBanner = 'Manual retry failed');
    } finally {
      if (mounted) setState(() => _manualRetryId = null);
    }
  }

  Future<void> _deleteObservation(Observation obs) async {
    if (_syncing || obs.syncStatus == SyncStatus.uploading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible de supprimer pendant la synchronisation.'),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer cette observation ?'),
        content: const Text(
          'Cette action supprimera l’observation de la file locale. '
          'Si elle a déjà été synchronisée, les données en ligne '
          'ne seront pas supprimées par cette action.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await widget.repository.deleteById(obs.id);
      await _load();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Observation supprimée de la file locale.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de la suppression : $e')),
      );
    }
  }

  bool _isFullySynced(Observation obs) =>
      queueSyncState(obs) == QueueSyncState.fullySynced;

  bool _needsAttention(Observation obs) {
    final state = queueSyncState(obs);
    return state == QueueSyncState.metadataSyncedPhotoFailed ||
        state == QueueSyncState.laterStepIncomplete ||
        state == QueueSyncState.manualReview ||
        state == QueueSyncState.manualRetryInProgress ||
        obs.syncStatus == SyncStatus.failed;
  }

  List<Observation> get _pending => _all
      .where((o) =>
          !_isFullySynced(o) &&
          !_needsAttention(o) &&
          (o.syncStatus == SyncStatus.pending ||
              o.syncStatus == SyncStatus.uploading))
      .toList();
  List<Observation> get _failed =>
      _all.where((o) => !_isFullySynced(o) && _needsAttention(o)).toList();
  List<Observation> get _synced => _all.where(_isFullySynced).toList();

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
          if (_syncing)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                key: const ValueKey('cancel_sync_button'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _cancelSync,
                icon: const Icon(Icons.close_rounded, size: 16),
                label: const Text('Cancel',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            )
          else if (hasPendingOrFailed)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                key: const ValueKey('sync_all_button'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.teal,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _syncAll,
                icon: const Icon(Icons.cloud_upload_outlined, size: 16),
                label: const Text('Sync All',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ),
        ],
        bottom: _all.isEmpty
            ? null
            : TabBar(
                controller: _tab,
                indicatorColor: AppColors.tealGlow,
                indicatorWeight: 2,
                labelColor: AppColors.tealGlow,
                unselectedLabelColor: Colors.white54,
                labelStyle:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                tabs: [
                  Tab(text: 'Pending (${_pending.length})'),
                  Tab(text: 'Failed (${_failed.length})'),
                  Tab(text: 'Synced (${_synced.length})'),
                ],
              ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.teal)))
          : _loadError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: AppColors.syncFailed, size: 36),
                    const SizedBox(height: 12),
                    Text(_loadError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _load, child: const Text('Retry')),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                if (_syncing)
                  Container(
                    width: double.infinity,
                    color: AppColors.navyLight,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Syncing in progress…',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                        TextButton(
                          onPressed: _cancelSync,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.orangeAccent,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Cancel',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  )
                else if (_statusBanner != null)
                  Container(
                    width: double.infinity,
                    color: _statusBlocked || _statusBanner!.contains('cancelled')
                        ? Colors.orange.shade900
                        : AppColors.navyLight,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        Icon(
                          _statusBlocked || _statusBanner!.contains('cancelled')
                              ? Icons.warning_amber_rounded
                              : Icons.check_circle_outline,
                          color: _statusBlocked ||
                                  _statusBanner!.contains('cancelled')
                              ? Colors.orangeAccent
                              : AppColors.syncDone,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _statusBanner!,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: _all.isEmpty
                      ? _buildEmpty()
                      : TabBarView(
                          controller: _tab,
                          children: [
                            _ObsList(
                              observations: _pending,
                              emptyMessage: 'All caught up!',
                              emptyIcon: Icons.cloud_done_rounded,
                              emptyColor: AppColors.syncDone,
                              onDelete: _deleteObservation,
                              deletingDisabled: _syncing,
                            ),
                            _ObsList(
                              observations: _failed,
                              emptyMessage: 'No failed uploads.',
                              emptyIcon: Icons.check_circle_outline_rounded,
                              emptyColor: AppColors.syncDone,
                              onDelete: _deleteObservation,
                              deletingDisabled: _syncing || _manualRetryId != null,
                              onRetry: _syncing ? null : _syncAll,
                              onManualRetry: _retryNeedsReview,
                              manualRetryId: _manualRetryId,
                            ),
                            _ObsList(
                              observations: _synced,
                              emptyMessage: 'Nothing synced yet.',
                              emptyIcon: Icons.cloud_outlined,
                              emptyColor: AppColors.textFaintOnDark,
                              onDelete: _deleteObservation,
                              deletingDisabled: _syncing,
                            ),
                          ],
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildEmpty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
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
    required this.onDelete,
    required this.deletingDisabled,
    this.onRetry,
    this.onManualRetry,
    this.manualRetryId,
  });

  final List<Observation> observations;
  final String emptyMessage;
  final IconData emptyIcon;
  final Color emptyColor;
  final Future<void> Function(Observation) onDelete;
  final bool deletingDisabled;
  final Future<void> Function()? onRetry;
  final Future<void> Function(Observation)? onManualRetry;
  final String? manualRetryId;

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
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Colors.black54)),
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
        itemBuilder: (_, i) => _ObsCard(
          key: ValueKey('queue-card-${observations[i].id}'),
          obs: observations[i],
          onDelete: onDelete,
          deletingDisabled: deletingDisabled,
          onRetry: onRetry,
          onManualRetry: onManualRetry,
          manualRetryInProgress: manualRetryId == observations[i].id,
        ),
      ),
    );
  }
}

// ── Obs card ──────────────────────────────────────────────────────────────────

class _ObsCard extends StatelessWidget {
  const _ObsCard({
    super.key,
    required this.obs,
    required this.onDelete,
    required this.deletingDisabled,
    this.onRetry,
    this.onManualRetry,
    this.manualRetryInProgress = false,
  });

  final Observation obs;
  final Future<void> Function(Observation) onDelete;
  final bool deletingDisabled;
  final Future<void> Function()? onRetry;
  final Future<void> Function(Observation)? onManualRetry;
  final bool manualRetryInProgress;

  QueueSyncState get _state => queueSyncState(
        obs,
        manualRetryInProgress: manualRetryInProgress,
      );

  Color get _statusColor => switch (_state) {
        QueueSyncState.notYetSynced => obs.syncStatus == SyncStatus.uploading
            ? AppColors.tealLight
            : AppColors.syncPending,
        QueueSyncState.metadataSyncedPhotoFailed => AppColors.syncFailed,
        QueueSyncState.laterStepIncomplete => AppColors.syncFailed,
        QueueSyncState.fullySynced => AppColors.syncDone,
        QueueSyncState.manualReview => AppColors.syncFailed,
        QueueSyncState.manualRetryInProgress => AppColors.tealLight,
      };

  String get _statusLabel => switch (_state) {
        QueueSyncState.notYetSynced =>
          obs.syncStatus == SyncStatus.uploading ? 'UPLOADING' : 'NOT SYNCED',
        QueueSyncState.metadataSyncedPhotoFailed => 'PHOTO FAILED',
        QueueSyncState.laterStepIncomplete => 'THUMBNAIL FAILED',
        QueueSyncState.fullySynced => 'SYNCED',
        QueueSyncState.manualReview => 'NEEDS REVIEW',
        QueueSyncState.manualRetryInProgress => 'RETRYING',
      };

  IconData get _statusIcon => switch (_state) {
        QueueSyncState.fullySynced => Icons.cloud_done_rounded,
        QueueSyncState.manualReview => Icons.error_outline_rounded,
        QueueSyncState.manualRetryInProgress => Icons.cloud_sync_rounded,
        QueueSyncState.metadataSyncedPhotoFailed => Icons.cloud_off_rounded,
        QueueSyncState.laterStepIncomplete => Icons.cloud_off_rounded,
        QueueSyncState.notYetSynced => obs.syncStatus == SyncStatus.uploading
            ? Icons.cloud_sync_rounded
            : Icons.cloud_upload_outlined,
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
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
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
                      width: 52,
                      height: 52,
                      child: ObservationPhoto(observation: obs),
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
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700)),
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
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(_statusIcon, size: 10, color: _statusColor),
                              const SizedBox(width: 3),
                              Text(_statusLabel,
                                  style: TextStyle(
                                      color: _statusColor,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700)),
                            ]),
                          ),
                          IconButton(
                            tooltip: 'Supprimer cette observation',
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.red,
                              size: 20,
                            ),
                            onPressed:
                                deletingDisabled ? null : () => onDelete(obs),
                          ),
                        ]),
                        const SizedBox(height: 4),
                        Text(
                            '${obs.detections.length} anomaly${obs.detections.length == 1 ? '' : 's'} · ${obs.actor}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(
                          queueStatusMessage(
                            obs,
                            manualRetryInProgress: manualRetryInProgress,
                          ),
                          key: ValueKey('queue-status-${obs.id}'),
                          style: TextStyle(
                            color: _statusColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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
                if (_state == QueueSyncState.manualReview) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: deletingDisabled || onManualRetry == null
                          ? null
                          : () => onManualRetry!(obs),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: Text(onManualRetry == null
                          ? 'Manual retry is unavailable.'
                          : 'Retry once'),
                    ),
                  ),
                ] else if (onRetry != null &&
                    (_state == QueueSyncState.metadataSyncedPhotoFailed ||
                        _state == QueueSyncState.laterStepIncomplete ||
                        obs.syncStatus == SyncStatus.failed)) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: deletingDisabled ? null : onRetry,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Retry'),
                    ),
                  ),
                ],
                if (obs.syncError != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.syncFailed.withAlpha(12),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: AppColors.syncFailed.withAlpha(40)),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.mockWarning.withAlpha(15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('⚠ DEMO MOCK INFERENCE',
                        style: TextStyle(
                            color: AppColors.mockWarning,
                            fontSize: 10,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

}
