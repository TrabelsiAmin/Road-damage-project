
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/app_colors.dart';
import '../core/constants.dart';
import 'home_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with TickerProviderStateMixin {
  String? _selectedActor;
  late AnimationController _heroCtrl;
  late AnimationController _pulseCtrl;
  late Animation<double> _heroFade;
  late Animation<Offset> _heroSlide;
  late Animation<double> _pulsAnim;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    _heroCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));
    _heroFade = CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOut);
    _heroSlide = Tween<Offset>(
      begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOutCubic));

    _pulseCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2200))
        ..repeat(reverse: true);
    _pulsAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _heroCtrl.forward();
  }

  @override
  void dispose() {
    _heroCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _proceed() {
    if (_selectedActor == null) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (_, anim, __) => HomeScreen(initialActor: _selectedActor!),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: Stack(
        children: [
          // ── Background decoration ─────────────────────────────────────────
          Positioned.fill(child: _Background(pulse: _pulsAnim)),

          // ── Content ───────────────────────────────────────────────────────
          SafeArea(
            child: FadeTransition(
              opacity: _heroFade,
              child: SlideTransition(
                position: _heroSlide,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),

                      // ── Logo ───────────────────────────────────────────────
                      const _Logo(),
                      const SizedBox(height: 10),

                      // ── Tagline ────────────────────────────────────────────
                      Text(
                        'Detect. Map. Report.',
                        style: TextStyle(
                          color: AppColors.tealGlow,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 2.0,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'AI-powered road damage\ninspection, offline-first.',
                        style: TextStyle(
                          color: AppColors.textSubtleOnDark,
                          fontSize: 15,
                          height: 1.55,
                        ),
                      ),

                      const SizedBox(height: 36),

                      // ── Institution label ──────────────────────────────────
                      Row(children: [
                        Container(
                          width: 2, height: 14,
                          decoration: BoxDecoration(
                            color: AppColors.teal,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'SELECT YOUR INSTITUTION',
                          style: TextStyle(
                            color: AppColors.textSubtleOnDark,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ]),
                      const SizedBox(height: 14),

                      // ── Actor cards ────────────────────────────────────────
                      ...TariqMapConstants.actors.asMap().entries.map((e) {
                        return TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.0, end: 1.0),
                          duration: Duration(milliseconds: 300 + e.key * 100),
                          curve: Curves.easeOutCubic,
                          builder: (_, v, child) => Opacity(
                            opacity: v,
                            child: Transform.translate(
                              offset: Offset(0, 20 * (1 - v)),
                              child: child,
                            ),
                          ),
                          child: _ActorCard(
                            actor: e.value,
                            isSelected: _selectedActor == e.value,
                            onTap: () => setState(() => _selectedActor = e.value),
                          ),
                        );
                      }),

                      const Spacer(),

                      // ── CTA button ─────────────────────────────────────────
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 300),
                        opacity: _selectedActor != null ? 1.0 : 0.35,
                        child: _BeginButton(
                          enabled: _selectedActor != null,
                          onTap: _proceed,
                        ),
                      ),

                      const SizedBox(height: 14),

                      // ── Disclaimer ─────────────────────────────────────────
                      Center(
                        child: Text(
                          'Inference runs fully on-device.\nNo data uploaded without your approval.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textFaintOnDark,
                            fontSize: 11,
                            height: 1.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Background ────────────────────────────────────────────────────────────────

class _Background extends StatelessWidget {
  const _Background({required this.pulse});
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: pulse,
    builder: (_, __) => CustomPaint(
      painter: _BgPainter(pulse.value),
    ),
  );
}

class _BgPainter extends CustomPainter {
  _BgPainter(this.pulse);
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    // gradient base
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(rect, Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF050F1C), Color(0xFF0A1929)],
      ).createShader(rect));

    // glowing circle top-right
    final cx = size.width * 0.85;
    final cy = size.height * 0.12;
    final r = size.width * 0.55 * pulse;
    canvas.drawCircle(Offset(cx, cy), r, Paint()
      ..color = const Color(0xFF0891B2).withAlpha(18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 80));

    // second glow bottom-left
    canvas.drawCircle(
      Offset(size.width * 0.05, size.height * 0.75),
      size.width * 0.40 * pulse,
      Paint()
        ..color = const Color(0xFF06B6D4).withAlpha(12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60),
    );

    // grid lines
    final linePaint = Paint()
      ..color = const Color(0xFF1E3A54).withAlpha(60)
      ..strokeWidth = 0.5;
    const step = 42.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }
  }

  @override
  bool shouldRepaint(_BgPainter old) => old.pulse != pulse;
}

// ── Logo ──────────────────────────────────────────────────────────────────────

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(
      width: 52, height: 52,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.teal, AppColors.tealGlow],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.teal.withAlpha(100),
            blurRadius: 20, spreadRadius: 1),
        ],
      ),
      child: const Icon(Icons.add_road_rounded, color: Colors.white, size: 30),
    ),
    const SizedBox(width: 16),
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'TariqMap',
          style: TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w900,
            letterSpacing: -1,
          ),
        ),
        Text(
          'طريق',
          style: TextStyle(
            color: AppColors.tealGlow,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
      ],
    ),
  ]);
}

// ── Actor card ────────────────────────────────────────────────────────────────

class _ActorCard extends StatelessWidget {
  const _ActorCard({
    required this.actor,
    required this.isSelected,
    required this.onTap,
  });

  final String actor;
  final bool   isSelected;
  final VoidCallback onTap;

  IconData get _icon => switch (actor) {
    'Municipality'          => Icons.location_city_rounded,
    'Ministry of Equipment' => Icons.engineering_rounded,
    'Tunisia Autoroutes'    => Icons.directions_car_filled_rounded,
    _                       => Icons.business_rounded,
  };

  String get _subtitle => switch (actor) {
    'Municipality'          => 'Urban roads · Local infrastructure',
    'Ministry of Equipment' => 'National roads · Highways (DGRR)',
    'Tunisia Autoroutes'    => 'Motorways · Toll roads',
    _                       => '',
  };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.teal.withAlpha(28)
              : AppColors.cardDark,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? AppColors.teal : AppColors.borderDark,
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: isSelected
              ? [BoxShadow(
                  color: AppColors.teal.withAlpha(50),
                  blurRadius: 16, spreadRadius: 0)]
              : [],
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.teal.withAlpha(60)
                    : AppColors.navyLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_icon,
                color: isSelected ? AppColors.tealGlow : AppColors.textSubtleOnDark,
                size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    actor,
                    style: TextStyle(
                      color: isSelected ? Colors.white : AppColors.textSubtleOnDark,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _subtitle,
                    style: TextStyle(
                      color: isSelected
                          ? AppColors.textSubtleOnDark
                          : AppColors.textFaintOnDark,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedOpacity(
              opacity: isSelected ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                width: 22, height: 22,
                decoration: BoxDecoration(
                  color: AppColors.teal,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Begin button ──────────────────────────────────────────────────────────────

class _BeginButton extends StatefulWidget {
  const _BeginButton({required this.enabled, required this.onTap});
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_BeginButton> createState() => _BeginButtonState();
}

class _BeginButtonState extends State<_BeginButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleCtrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 100));
    _scale = Tween<double>(begin: 1.0, end: 0.97)
        .animate(CurvedAnimation(parent: _scaleCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

  void _onTapDown(_) => _scaleCtrl.forward();
  void _onTapUp(_) {
    _scaleCtrl.reverse();
    if (widget.enabled) widget.onTap();
  }
  void _onTapCancel() => _scaleCtrl.reverse();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 17),
          decoration: BoxDecoration(
            gradient: widget.enabled
                ? const LinearGradient(
                    colors: [AppColors.teal, AppColors.tealGlow],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  )
                : null,
            color: widget.enabled ? null : AppColors.navyLight,
            borderRadius: BorderRadius.circular(16),
            boxShadow: widget.enabled
                ? [BoxShadow(
                    color: AppColors.teal.withAlpha(90),
                    blurRadius: 20, offset: const Offset(0, 6))]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              const Text(
                'Begin Inspection',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
