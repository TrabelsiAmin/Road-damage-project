import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import '../core/app_colors.dart';
import '../core/constants.dart';
import '../models/observation.dart';
import '../services/detection_service.dart';
import '../services/observation_repository.dart';
import '../data/remote/api_client.dart';
import '../services/territorial_service.dart';
import 'camera_detection_screen.dart';
import 'model_status_screen.dart';
import 'offline_queue_screen.dart';
import 'result_screen.dart';
import 'settings_screen.dart';
import 'video_import_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.initialActor});
  final String initialActor;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _picker = ImagePicker();
  final _uuid   = const Uuid();

  // Services — async-initialised
  late DetectionService       _detection;
  late ObservationRepository  _repository;
  final _location = LocationService();

  bool _servicesReady = false;
  bool _busy          = false;
  String? _message;
  late String _actor;

  List<Observation> _observations = [];

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _actor = widget.initialActor;
    _initServices();
  }

  Future<void> _initServices() async {
    try {
      _detection  = await DetectionService.create();
      _repository = kIsWeb
          ? MemoryObservationRepository()
          : SqliteObservationRepository();

      // Recover stuck uploads from previous session
      final sync = SyncCoordinator(_repository, ApiClient());
      await sync.recoverStuckUploads();

      final loaded = await _repository.list();

      if (mounted) {
        setState(() {
          _observations = loaded;
          _servicesReady = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _message = 'Startup error: $e';
          _servicesReady = true;
        });
      }
    }
  }

  // ── Import from gallery ──────────────────────────────────────────────────────

  Future<void> _importFromGallery() async {
    setState(() { _busy = true; _message = null; });
    try {
      final picked = await _picker.pickImage(
          source: ImageSource.gallery, imageQuality: 92, maxWidth: 1600);
      if (picked == null) return;

      Position? position;
      try {
        position = await _location.currentPosition();
      } catch (e) {
        setState(() => _message =
            'GPS unavailable: $e. Observation is kept for later enrichment.');
      }

      final imageFile = File(picked.path);
      final results   = await _detection.detectAll(imageFile);
      final hasGps = position != null;
      final obs = Observation(
        id:           _uuid.v4(),
        captureId:    _uuid.v4(),
        imagePath:    picked.path,
        createdAt:    DateTime.now().toUtc(),
        latitude:     position?.latitude  ?? 0.0,
        longitude:    position?.longitude ?? 0.0,
        gpsAvailable: hasGps,
        accuracyMeters: position?.accuracy,
        actor:        _actor,
        agentResults: results,
      );

      await _repository.save(obs);
      if (mounted) {
        setState(() => _observations.insert(0, obs));
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => ResultScreen(observation: obs)),
        );
      }
    } catch (error) {
      setState(() => _message = error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Open live camera ────────────────────────────────────────────────────────

  Future<void> _openCamera() async {
    if (kIsWeb) {
      setState(() => _message = 'Live camera is not supported in the browser. Use Import instead.');
      return;
    }
    final result = await Navigator.of(context).push<Observation>(
      MaterialPageRoute<Observation>(
        builder: (_) => CameraDetectionScreen(
          detectionService: _detection,
          repository:       _repository,
          actor:            _actor,
        ),
        fullscreenDialog: true,
      ),
    );
    if (result != null && mounted) {
      setState(() => _observations.insert(0, result));
    }
  }

  // ── Open video import ───────────────────────────────────────────────────────

  Future<void> _openVideoImport() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VideoImportScreen(
          service:    _detection,
          actor:      _actor,
          repository: _repository,
        ),
      ),
    );
    // Reload to capture any saved video-frame observations
    final loaded = await _repository.list();
    if (mounted) setState(() => _observations = loaded);
  }

  // ── Sync ────────────────────────────────────────────────────────────────────

  Future<void> _syncAll() async {
    final sync = SyncCoordinator(_repository, ApiClient());
    await sync.syncPending();
    final loaded = await _repository.list();
    if (mounted) setState(() => _observations = loaded);
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final pending = _observations.where((o) => o.syncStatus == SyncStatus.pending).length;

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        title: Row(children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
              color: AppColors.teal, borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.add_road, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          const Text('TariqMap',
              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3)),
        ]),
        actions: [
          if (pending > 0)
            _PendingBadge(count: pending, onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => OfflineQueueScreen(
                repository: _repository, onSync: _syncAll)),
            )),
          IconButton(
            icon: const Icon(Icons.tune_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: !_servicesReady
          ? const Center(child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Initialising…', style: TextStyle(color: Colors.black45)),
              ],
            ))
          : RefreshIndicator(
              onRefresh: () async {
                final loaded = await _repository.list();
                setState(() => _observations = loaded);
              },
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ── Header ──────────────────────────────────────────────────
                  _HeaderCard(actor: _actor),
                  const SizedBox(height: 16),

                  // ── Action buttons ───────────────────────────────────────────
                  Row(children: [
                    Expanded(
                      flex: 3,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: AppColors.teal,
                        ),
                        onPressed: _busy ? null : _openCamera,
                        icon: const Icon(Icons.videocam_rounded, size: 22),
                        label: const Text('Live Camera',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: _busy ? null : _importFromGallery,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Import'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        foregroundColor: AppColors.teal,
                      ),
                      onPressed: _busy ? null : _openVideoImport,
                      icon: const Icon(Icons.video_file_outlined),
                      label: const Text('Import Video'),
                    ),
                  ),

                  if (_busy) const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  if (_message != null) Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.withAlpha(15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.withAlpha(60)),
                      ),
                      child: Text(_message!,
                          style: const TextStyle(color: Colors.red, fontSize: 12)),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Model status banner ────────────────────────────────────
                  _ModelBanner(
                    service: _detection,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ModelStatusScreen(service: _detection)),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Observations list ──────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Recent Observations',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold)),
                      Text('${_observations.length} total',
                          style: const TextStyle(color: Colors.black45, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 10),

                  if (_observations.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(children: [
                          Icon(Icons.add_road_rounded, size: 48,
                              color: AppColors.teal.withAlpha(120)),
                          const SizedBox(height: 12),
                          const Text('No observations yet.',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          const Text('Tap "Live Camera" or "Import" to begin.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.black45)),
                        ]),
                      ),
                    ),

                  ..._observations.map((o) => _ObservationCard(
                    observation: o,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ResultScreen(observation: o)),
                    ),
                  )),
                ],
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.actor});
  final String actor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [AppColors.navy, AppColors.navyMid],
        begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Road Inspection',
            style: TextStyle(color: Colors.white,
                fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
        const SizedBox(height: 4),
        Text('Actor: $actor',
            style: const TextStyle(color: Colors.white54, fontSize: 13)),
        const SizedBox(height: 4),
        const Text('Detect and log road damage — fully offline.',
            style: TextStyle(color: Colors.white38, fontSize: 12)),
      ],
    ),
  );
}

class _PendingBadge extends StatelessWidget {
  const _PendingBadge({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.syncPending.withAlpha(200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        const Icon(Icons.cloud_upload_outlined, size: 14, color: Colors.white),
        const SizedBox(width: 4),
        Text('$count', style: const TextStyle(
            fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
      ]),
    ),
  );
}

class _ModelBanner extends StatelessWidget {
  const _ModelBanner({required this.service, required this.onTap});
  final DetectionService service;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isMock = service.usingMock;
    final isPartial = service.partialMock;
    final color = isMock ? AppColors.mockWarning : (isPartial ? AppColors.partialWarning : AppColors.syncDone);
    final icon  = isMock ? Icons.science_outlined : (isPartial ? Icons.warning_amber_outlined : Icons.verified_outlined);
    final text  = isMock
        ? 'DEMO MOCK INFERENCE active — tap for model status'
        : (isPartial ? 'PARTIAL REAL inference — some agents mocked' : 'Real on-device TFLite inference');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withAlpha(100)),
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(text,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600))),
          Icon(Icons.chevron_right, color: color, size: 16),
        ]),
      ),
    );
  }
}

class _ObservationCard extends StatelessWidget {
  const _ObservationCard({required this.observation, required this.onTap});
  final Observation  observation;
  final VoidCallback onTap;

  Color _priorityColor(double s) => AppColors.forPriority(s);

  @override
  Widget build(BuildContext context) {
    final o = observation;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Row(children: [
          // Thumbnail
          ClipRRect(
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
            child: SizedBox(
              width: 90, height: 90,
              child: kIsWeb
                  ? Image.network(o.imagePath, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder())
                  : Image.file(File(o.imagePath), fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder()),
            ),
          ),
          // Info
          Expanded(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 8, height: 8,
                    decoration: BoxDecoration(
                        color: _priorityColor(o.priorityScore), shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text('${o.priorityScore.toStringAsFixed(0)}/100 · ${o.priorityLabel}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const Spacer(),
                Text(DateFormat('HH:mm').format(o.createdAt.toLocal()),
                    style: const TextStyle(color: Colors.black38, fontSize: 11)),
              ]),
              const SizedBox(height: 4),
              Text(o.actor, style: const TextStyle(color: Colors.black54, fontSize: 12)),
              const SizedBox(height: 3),
              Text(
                '${o.detections.length} detection${o.detections.length == 1 ? '' : 's'}  '
                '·  ${o.latitude.toStringAsFixed(4)}, ${o.longitude.toStringAsFixed(4)}',
                style: const TextStyle(fontSize: 11, color: Colors.black38),
                overflow: TextOverflow.ellipsis,
              ),
              if (o.anyMock)
                const Padding(
                  padding: EdgeInsets.only(top: 3),
                  child: Text('⚠ MOCK', style: TextStyle(
                      color: AppColors.mockWarning, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
            ]),
          )),
          // Sync icon
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Icon(
              switch (o.syncStatus) {
                SyncStatus.pending     => Icons.cloud_upload_outlined,
                SyncStatus.uploading   => Icons.cloud_sync_outlined,
                SyncStatus.synced      => Icons.cloud_done_outlined,
                SyncStatus.failed      => Icons.cloud_off_outlined,
                SyncStatus.needsReview => Icons.error_outline,
              },
              color: switch (o.syncStatus) {
                SyncStatus.synced  => AppColors.syncDone,
                SyncStatus.failed  => AppColors.syncFailed,
                SyncStatus.needsReview => AppColors.syncFailed,
                _                  => AppColors.syncPending,
              },
              size: 20,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _placeholder() => Container(
    color: Colors.grey.shade100,
    child: const Icon(Icons.image_not_supported_outlined, color: Colors.black26),
  );
}

