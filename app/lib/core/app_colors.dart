import 'package:flutter/material.dart';

/// TariqMap design tokens — shared across the entire application.
///
/// All colours are intentionally defined here so that agent-specific
/// tints, severity indicators, and palette constants are never
/// duplicated across screens or painters.
class AppColors {
  AppColors._();

  // ── Brand palette ────────────────────────────────────────────────────────
  static const navy     = Color(0xFF0B1F33);
  static const navyMid  = Color(0xFF142C46);
  static const navyLight= Color(0xFF1E3A56);
  static const teal     = Color(0xFF0E7490);
  static const tealLight= Color(0xFF0EA5C9);
  static const offWhite = Color(0xFFF5F7FA);
  static const surface  = Color(0xFFFFFFFF);

  // ── Severity / priority ──────────────────────────────────────────────────
  static const critical  = Color(0xFFFF1744);  // priority >= 70
  static const high      = Color(0xFFFF9800);  // priority >= 40
  static const medium    = Color(0xFFFFD600);  // priority >= 20
  static const low       = Color(0xFF4CAF50);  // priority < 20

  // ── Agent / class colours ────────────────────────────────────────────────
  // cracks agent
  static const d00Color = Color(0xFFFF6B35);   // Longitudinal crack  — orange
  static const d10Color = Color(0xFFFFD700);   // Transverse crack    — yellow

  // pavement agent
  static const d20Color = Color(0xFFE040FB);   // Alligator crack     — purple
  static const d40Color = Color(0xFFFF1744);   // Pothole             — red

  // surface agent
  static const d50Color = Color(0xFF00E5FF);   // Faded crossing      — cyan
  static const d60Color = Color(0xFF69FF47);   // Faded lane          — green
  static const d90Color = Color(0xFFFF9800);   // Rutting             — amber

  // ── UI chrome ────────────────────────────────────────────────────────────
  static const offlineWarning = Color(0xFFF59E0B);
  static const mockWarning    = Color(0xFFF97316);
  static const partialWarning = Color(0xFFEF4444);
  static const syncPending    = Color(0xFFFF9800);
  static const syncDone       = Color(0xFF4CAF50);
  static const syncFailed     = Color(0xFFEF4444);

  /// Returns the display colour for a given D-code.
  static Color forClassCode(String code) => switch (code) {
    'D00' => d00Color,
    'D10' => d10Color,
    'D20' => d20Color,
    'D40' => d40Color,
    'D50' => d50Color,
    'D60' => d60Color,
    'D90' => d90Color,
    _     => Colors.white,
  };

  /// Returns a priority colour for a score in [0..100].
  static Color forPriority(double score) {
    if (score >= 70) return critical;
    if (score >= 40) return high;
    if (score >= 20) return medium;
    return low;
  }
}
