import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/constants.dart';
import 'home_screen.dart';

/// Welcome screen — shown on first launch or when no actor is selected.
///
/// The user selects their operating institution before any detection begins.
/// This ensures every observation is stamped with the correct actor from the start.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  String? _selectedActor;
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _proceed() {
    if (_selectedActor == null) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => HomeScreen(initialActor: _selectedActor!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Logo / header ──────────────────────────────────────────
                const _Header(),
                const SizedBox(height: 48),

                // ── Actor cards ────────────────────────────────────────────
                const Text(
                  'Select your institution',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),

                ...TariqMapConstants.actors.map((actor) => _ActorCard(
                  actor: actor,
                  isSelected: _selectedActor == actor,
                  onTap: () => setState(() => _selectedActor = actor),
                )),

                const Spacer(),

                // ── Proceed button ─────────────────────────────────────────
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 250),
                  opacity: _selectedActor != null ? 1.0 : 0.35,
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.teal,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _selectedActor != null ? _proceed : null,
                      child: const Text(
                        'Begin Inspection',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Disclaimer ─────────────────────────────────────────────
                const Text(
                  'Inference runs fully on-device. No images are uploaded without your approval.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white30, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: AppColors.teal,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.add_road, color: Colors.white, size: 26),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'TariqMap',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            Text(
              'طريق — Road Damage Inspector',
              style: TextStyle(
                  color: Colors.white.withAlpha(140), fontSize: 12),
            ),
          ],
        ),
      ]),
      const SizedBox(height: 20),
      Text(
        'Offline-first on-device detection.\nCapture, analyse, and report road damage.',
        style: TextStyle(
          color: Colors.white.withAlpha(160),
          fontSize: 15,
          height: 1.5,
        ),
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Actor card
// ---------------------------------------------------------------------------

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
    'Municipality'          => Icons.location_city_outlined,
    'Ministry of Equipment' => Icons.engineering_outlined,
    'Tunisia Autoroutes'    => Icons.directions_car_outlined,
    _                       => Icons.business_outlined,
  };

  String get _subtitle => switch (actor) {
    'Municipality'          => 'Urban roads and local infrastructure',
    'Ministry of Equipment' => 'National roads and highways (DGRR)',
    'Tunisia Autoroutes'    => 'Motorways and toll roads',
    _                       => '',
  };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.teal.withAlpha(40)
              : AppColors.navyMid,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.teal : Colors.white12,
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: AppColors.teal.withAlpha(60), blurRadius: 12)]
              : [],
        ),
        child: Row(
          children: [
            Icon(_icon,
              color: isSelected ? AppColors.tealLight : Colors.white54,
              size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    actor,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _subtitle,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: AppColors.teal, size: 22),
          ],
        ),
      ),
    );
  }
}
