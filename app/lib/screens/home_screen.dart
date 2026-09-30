import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import '../core/app_colors.dart';

import '../models/observation.dart';
import '../services/detection_service.dart';
import '../services/observation_repository.dart';
import '../data/remote/api_client.dart';
import '../services/territorial_service.dart';
import 'camera_detection_screen.dart';
import 'live_stream_screen.dart';
import 'model_status_screen.dart';
import 'offline_queue_screen.dart';
import 'result_screen.dart';
import 'settings_screen.dart';
import 'video_import_screen.dart';
import '../widgets/dashboard_map.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.initialActor});
  final String initialActor;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final _picker = ImagePicker();
  final _uuid   = const Uuid();

  late DetectionService      _detection;
  late ObservationRepository _repository;
  final _location = LocationService();

  bool _servicesReady = false;
  bool _busy          = false;
  String? _message;
  late String _actor;
  List<Observation> _observations = [];

  late AnimationController _fadeCtrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _actor = widget.initialActor;

    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    _initServices();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _initServices() async {
    try {
      _detection  = await DetectionService.create();
      _repository = kIsWeb
          ? MemoryObservationRepository()
          : SqliteObservationRepository();

      final sync = SyncCoordinator(_repository, ApiClient());
      await sync.recoverStuckUploads();

      final loaded = await _repository.list();
      if (mounted) {
        setState(() {
          _observations = loaded;
          _servicesReady = true;
        });
        _fadeCtrl.forward();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _message = 'Startup error: $e';
          _servicesReady = true;
        });
        _fadeCtrl.forward();
      }
    }
  }

  Future<void> _importFromGallery() async {
    setState(() { _busy = true; _message = null; });
    try {
      final picked = await _picker.pickImage(
          source: ImageSource.gallery, imageQuality: 92, maxWidth: 1600);
      if (picked == null) return;

      Position? position;
      try {
        position = await _location.currentPosition();
      } catch (_) {}

      final imageFile = File(picked.path);
      final results   = await _detection.detectAll(imageFile);
      final obs = Observation(
        id:             _uuid.v4(),
        captureId:      _uuid.v4(),
        imagePath:      picked.path,
        createdAt:      DateTime.now().toUtc(),
        latitude:       position?.latitude  ?? 0.0,
        longitude:      position?.longitude ?? 0.0,
        accuracyMeters: position?.accuracy,
        actor:          _actor,
        agentResults:   results,
      );

      await _repository.save(obs);
      if (mounted) {
        setState(() => _observations.insert(0, obs));
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ResultScreen(observation: obs)));
      }
    } catch (error) {
      setState(() => _message = error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openCamera() async {
    if (kIsWeb) {
      setState(() => _message = 'Live camera is not supported in browser.');
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

  Future<void> _openLiveStream() async {
    if (kIsWeb) {
      setState(() => _message = 'Live streaming is not supported in browser.');
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => LiveStreamScreen(
        detectionService: _detection,
        repository:       _repository,
        actor:            _actor,
      ),
      fullscreenDialog: true,
    ));
    final loaded = await _repository.list();
    if (mounted) setState(() => _observations = loaded);
  }

  Future<void> _openVideoImport() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => VideoImportScreen(service: _detection, actor: _actor),
    ));
    final loaded = await _repository.list();
    if (mounted) setState(() => _observations = loaded);
  }

  Future<void> _syncAll() async {
    final sync = SyncCoordinator(_repository, ApiClient());
    await sync.syncPending();
    final loaded = await _repository.list();
    if (mounted) setState(() => _observations = loaded);
  }

  @override
  Widget build(BuildContext context) {
    final pending = _observations
        .where((o) => o.syncStatus == SyncStatus.pending).length;

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      body: !_servicesReady
          ? const _LoadingView()
          : FadeTransition(
              opacity: _fade,
              child: CustomScrollView(
                slivers: [
                  // ── Sliver App Bar ───────────────────────────────────────
                  _HomeAppBar(
                    actor: _actor,
                    pending: pending,
                    detection: _servicesReady ? _detection : null,
                    onQueue: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => OfflineQueueScreen(
                          repository: _repository, onSync: _syncAll))),
                    onSettings: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SettingsScreen())),
                    onModelStatus: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ModelStatusScreen(service: _detection))),
                  ),

                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 30),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([

                        // ── Action grid ────────────────────────────────────
                        const _SectionLabel('INSPECTION TOOLS'),
                        const SizedBox(height: 10),
                        _ActionGrid(
                          busy: _busy,
                          onLiveStream:    _openLiveStream,
                          onCamera:        _openCamera,
                          onImportImage:   _importFromGallery,
                          onImportVideo:   _openVideoImport,
                        ),

                        // ── Error / message banner ─────────────────────────
                        if (_message != null) ...[
                          const SizedBox(height: 14),
                          _MessageBanner(message: _message!,
                              onDismiss: () => setState(() => _message = null)),
                        ],

                        const SizedBox(height: 24),

                        // ── Map Dashboard ──────────────────────────────────
                        const _SectionLabel('ANOMALY MAP'),
                        const SizedBox(height: 10),
                        const SizedBox(
                          height: 260,
                          child: DashboardMap(),
                        ),
                        const SizedBox(height: 24),

                        // ── Stats row ──────────────────────────────────────
                        if (_observations.isNotEmpty) ...[
                          _StatsRow(observations: _observations),
                          const SizedBox(height: 24),
                        ],

                        // ── Observations list ──────────────────────────────
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const _SectionLabel('RECENT INSPECTIONS'),
                            if (_observations.isNotEmpty)
                              Text('${_observations.length}',
                                style: TextStyle(
                                  color: AppColors.teal,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                )),
                          ],
                        ),
                        const SizedBox(height: 10),

                        if (_observations.isEmpty)
                          const _EmptyState()
                        else
                          ..._observations.asMap().entries.map((e) =>
                            _ObservationCard(
                              observation: e.value,
                              index: e.key,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => ResultScreen(observation: e.value))),
                            )),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

// ── Loading ───────────────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.teal, AppColors.tealGlow]),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(Icons.add_road_rounded, color: Colors.white, size: 34),
        ),
        const SizedBox(height: 24),
        const SizedBox(
          width: 24, height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.teal),
          ),
        ),
        const SizedBox(height: 14),
        Text('Initialising AI models…',
          style: TextStyle(color: Colors.black38, fontSize: 13)),
      ],
    ),
  );
}

// ── Sliver App Bar ────────────────────────────────────────────────────────────

class _HomeAppBar extends StatelessWidget {
  const _HomeAppBar({
    required this.actor,
    required this.pending,
    required this.detection,
    required this.onQueue,
    required this.onSettings,
    required this.onModelStatus,
  });

  final String          actor;
  final int             pending;
  final DetectionService? detection;
  final VoidCallback    onQueue;
  final VoidCallback    onSettings;
  final VoidCallback    onModelStatus;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 160,
      pinned: true,
      backgroundColor: AppColors.navy,
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: _AppBarBackground(
          actor: actor,
          detection: detection,
          onModelStatus: onModelStatus,
        ),
      ),
      title: Row(children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.teal, AppColors.tealGlow]),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.add_road_rounded, color: Colors.white, size: 16),
        ),
        const SizedBox(width: 10),
        const Text('TariqMap',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 18,
            letterSpacing: -0.5,
          )),
      ]),
      actions: [
        if (pending > 0)
          GestureDetector(
            onTap: onQueue,
            child: Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.syncPending.withAlpha(220),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.cloud_upload_outlined, size: 14, color: Colors.white),
                const SizedBox(width: 4),
                Text('$pending',
                  style: const TextStyle(
                    color: Colors.white, fontSize: 12,
                    fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
        IconButton(
          icon: const Icon(Icons.settings_outlined, color: Colors.white),
          tooltip: 'Settings',
          onPressed: onSettings,
        ),
      ],
    );
  }
}

class _AppBarBackground extends StatelessWidget {
  const _AppBarBackground({
    required this.actor,
    required this.detection,
    required this.onModelStatus,
  });

  final String           actor;
  final DetectionService? detection;
  final VoidCallback     onModelStatus;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.navy, Color(0xFF0C2340)],
        ),
      ),
      child: Stack(
        children: [
          // subtle grid
          Positioned.fill(child: CustomPaint(painter: _GridPainter())),
          // glow
          Positioned(
            right: -30, top: -30,
            child: Container(
              width: 160, height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.teal.withAlpha(40),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 24, bottom: 16, right: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  const Icon(Icons.business_outlined,
                    size: 13, color: AppColors.tealGlow),
                  const SizedBox(width: 6),
                  Text(actor,
                    style: const TextStyle(
                      color: AppColors.tealGlow,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    )),
                ]),
                const SizedBox(height: 4),
                const Text('Road Inspection',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  )),
                const SizedBox(height: 10),
                // model status pill
                if (detection != null)
                  GestureDetector(
                    onTap: onModelStatus,
                    child: _ModelPill(detection: detection!),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFF1E3A54).withAlpha(50)
      ..strokeWidth = 0.5;
    const step = 36.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }
  @override bool shouldRepaint(_) => false;
}

class _ModelPill extends StatelessWidget {
  const _ModelPill({required this.detection});
  final DetectionService detection;

  @override
  Widget build(BuildContext context) {
    final isMock = detection.usingMock;
    final color  = isMock ? AppColors.mockWarning : AppColors.syncDone;
    final icon   = isMock ? Icons.science_outlined : Icons.verified_outlined;
    final label  = isMock ? 'DEMO MODE' : 'TFLite AI ACTIVE';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(22),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(80), width: 1),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 5),
        Text(label,
          style: TextStyle(
            color: color, fontSize: 10, fontWeight: FontWeight.w700,
            letterSpacing: 0.8)),
        const SizedBox(width: 4),
        Icon(Icons.chevron_right, size: 12, color: color),
      ]),
    );
  }
}

// ── Action grid ───────────────────────────────────────────────────────────────

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({
    required this.busy,
    required this.onLiveStream,
    required this.onCamera,
    required this.onImportImage,
    required this.onImportVideo,
  });

  final bool         busy;
  final VoidCallback onLiveStream;
  final VoidCallback onCamera;
  final VoidCallback onImportImage;
  final VoidCallback onImportVideo;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Primary full-width — Live Stream
        _ActionButton(
          label: 'Live Stream',
          subtitle: 'Record & upload to cloud',
          icon: Icons.fiber_manual_record_rounded,
          gradient: const [Color(0xFFE11D48), Color(0xFFBE123C)],
          glow: const Color(0xFFE11D48),
          enabled: !busy,
          onTap: onLiveStream,
          large: true,
        ),
        const SizedBox(height: 10),
        // 2-column row
        Row(children: [
          Expanded(
            flex: 3,
            child: _ActionButton(
              label: 'Quick Scan',
              subtitle: 'Snap & detect',
              icon: Icons.camera_alt_rounded,
              gradient: const [AppColors.teal, AppColors.tealGlow],
              glow: AppColors.teal,
              enabled: !busy,
              onTap: onCamera,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: _ActionButton(
              label: 'Import',
              subtitle: 'From gallery',
              icon: Icons.photo_library_rounded,
              gradient: const [Color(0xFF7C3AED), Color(0xFF9333EA)],
              glow: const Color(0xFF7C3AED),
              enabled: !busy,
              onTap: onImportImage,
            ),
          ),
        ]),
        const SizedBox(height: 10),
        // Video import full-width
        _ActionButton(
          label: 'Import Video',
          subtitle: 'Analyse frame by frame',
          icon: Icons.video_file_rounded,
          gradient: const [Color(0xFF0F766E), Color(0xFF14B8A6)],
          glow: const Color(0xFF0F766E),
          enabled: !busy,
          onTap: onImportVideo,
          secondary: true,
        ),
        // Loading indicator
        if (busy) const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(child: SizedBox(
            width: 22, height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.teal)),
          )),
        ),
      ],
    );
  }
}

class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.glow,
    required this.enabled,
    required this.onTap,
    this.large    = false,
    this.secondary = false,
  });

  final String     label;
  final String     subtitle;
  final IconData   icon;
  final List<Color> gradient;
  final Color      glow;
  final bool       enabled;
  final VoidCallback onTap;
  final bool       large;
  final bool       secondary;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 90));
    _scale = Tween<double>(begin: 1.0, end: 0.96)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final verticalPad = widget.large ? 18.0 : 14.0;

    return GestureDetector(
      onTapDown: (_) { if (widget.enabled) _ctrl.forward(); },
      onTapUp: (_) {
        _ctrl.reverse();
        if (widget.enabled) widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: widget.secondary
            ? Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(vertical: verticalPad),
                decoration: BoxDecoration(
                  color: widget.gradient.first.withAlpha(18),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: widget.gradient.first.withAlpha(80),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(widget.icon, size: 20, color: widget.gradient.last),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(widget.label,
                          style: TextStyle(
                            color: widget.gradient.last,
                            fontSize: 14, fontWeight: FontWeight.w700)),
                        Text(widget.subtitle,
                          style: TextStyle(
                            color: widget.gradient.first.withAlpha(180),
                            fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              )
            : Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: 20, vertical: verticalPad),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: widget.enabled
                        ? widget.gradient
                        : [Colors.grey.shade300, Colors.grey.shade400],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: widget.enabled
                      ? [BoxShadow(
                          color: widget.glow.withAlpha(70),
                          blurRadius: 16, offset: const Offset(0, 6))]
                      : [],
                ),
                child: Row(
                  children: [
                    Container(
                      width: widget.large ? 40 : 34,
                      height: widget.large ? 40 : 34,
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(30),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(widget.icon,
                        color: Colors.white,
                        size: widget.large ? 22 : 18),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(widget.label,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: widget.large ? 16 : 14,
                            fontWeight: FontWeight.w800,
                          )),
                        Text(widget.subtitle,
                          style: TextStyle(
                            color: Colors.white.withAlpha(180),
                            fontSize: 11,
                          )),
                      ],
                    ),
                    const Spacer(),
                    Icon(Icons.arrow_forward_ios_rounded,
                      color: Colors.white.withAlpha(160), size: 14),
                  ],
                ),
              ),
      ),
    );
  }
}

// ── Stats row ─────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.observations});
  final List<Observation> observations;

  @override
  Widget build(BuildContext context) {
    final total    = observations.length;
    final anomalies = observations.fold<int>(0, (s, o) => s + o.detections.length);
    final synced   = observations.where((o) => o.syncStatus == SyncStatus.synced).length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withAlpha(60),
            blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatItem(value: '$total', label: 'Sessions',
            icon: Icons.camera_alt_outlined),
          _Divider(),
          _StatItem(value: '$anomalies', label: 'Anomalies',
            icon: Icons.warning_amber_rounded, color: AppColors.high),
          _Divider(),
          _StatItem(value: '$synced', label: 'Synced',
            icon: Icons.cloud_done_outlined, color: AppColors.syncDone),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 1, height: 32,
    color: AppColors.borderDark,
  );
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.value,
    required this.label,
    required this.icon,
    this.color = AppColors.tealGlow,
  });

  final String   value;
  final String   label;
  final IconData icon;
  final Color    color;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(height: 4),
      Text(value,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w900,
        )),
      Text(label,
        style: const TextStyle(
          color: AppColors.textSubtleOnDark,
          fontSize: 10,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
        )),
    ],
  );
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: AppColors.teal,
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.5,
    ),
  );
}

// ── Message banner ────────────────────────────────────────────────────────────

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({required this.message, required this.onDismiss});
  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: AppColors.syncFailed.withAlpha(15),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.syncFailed.withAlpha(60)),
    ),
    child: Row(children: [
      const Icon(Icons.error_outline, color: AppColors.syncFailed, size: 18),
      const SizedBox(width: 10),
      Expanded(child: Text(message,
        style: const TextStyle(
          color: AppColors.syncFailed, fontSize: 12))),
      GestureDetector(
        onTap: onDismiss,
        child: const Icon(Icons.close, size: 16, color: AppColors.syncFailed)),
    ]),
  );
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(32),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.borderLight),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            color: AppColors.teal.withAlpha(15),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.add_road_rounded,
            size: 32, color: AppColors.teal.withAlpha(180)),
        ),
        const SizedBox(height: 14),
        const Text('No inspections yet',
          style: TextStyle(
            fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 6),
        Text('Use Live Stream or Quick Scan above\nto start detecting road damage.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.black45, fontSize: 13, height: 1.4)),
      ],
    ),
  );
}

// ── Observation card ──────────────────────────────────────────────────────────

class _ObservationCard extends StatelessWidget {
  const _ObservationCard({
    required this.observation,
    required this.index,
    required this.onTap,
  });

  final Observation  observation;
  final int          index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final o = observation;
    final priorityColor = AppColors.forPriority(o.priorityScore);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 200 + index * 50),
      curve: Curves.easeOutCubic,
      builder: (_, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, 16 * (1 - v)), child: child),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderLight),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(8),
              blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Row(
              children: [
                // Priority strip
                Container(
                  width: 4,
                  height: 80,
                  margin: const EdgeInsets.only(left: 0),
                  decoration: BoxDecoration(
                    color: priorityColor,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(16)),
                  ),
                ),
                // Thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.zero,
                  child: SizedBox(
                    width: 80, height: 80,
                    child: kIsWeb
                        ? Image.network(o.imagePath, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _thumb())
                        : Image.file(File(o.imagePath), fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _thumb()),
                  ),
                ),
                // Info
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
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
                              '${o.priorityScore.toStringAsFixed(0)} · ${o.priorityLabel}',
                              style: TextStyle(
                                color: priorityColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              )),
                          ),
                          const Spacer(),
                          Text(
                            DateFormat('HH:mm').format(o.createdAt.toLocal()),
                            style: const TextStyle(
                              color: Colors.black38, fontSize: 10)),
                        ]),
                        const SizedBox(height: 5),
                        Text(
                          '${o.detections.length} anomaly${o.detections.length == 1 ? '' : 's'} detected',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                        const SizedBox(height: 3),
                        Text(
                          '${o.actor}  ·  ${o.latitude.toStringAsFixed(4)}, ${o.longitude.toStringAsFixed(4)}',
                          style: const TextStyle(
                            fontSize: 11, color: Colors.black38),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
                // Sync icon
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _SyncDot(status: o.syncStatus),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _thumb() => Container(
    color: AppColors.offWhite,
    child: const Icon(Icons.image_not_supported_outlined,
      color: Colors.black26),
  );
}

class _SyncDot extends StatelessWidget {
  const _SyncDot({required this.status});
  final SyncStatus status;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (status) {
      SyncStatus.synced    => (Icons.cloud_done_rounded, AppColors.syncDone),
      SyncStatus.uploading => (Icons.cloud_sync_rounded, AppColors.tealLight),
      SyncStatus.failed    => (Icons.cloud_off_rounded, AppColors.syncFailed),
      SyncStatus.needsReview => (Icons.error_outline, AppColors.syncFailed),
      _                    => (Icons.cloud_upload_outlined, AppColors.syncPending),
    };
    return Icon(icon, color: color, size: 18);
  }
}
