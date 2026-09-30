import 'package:flutter/material.dart';

/// TariqMap design tokens — shared across the entire application.
class AppColors {
  AppColors._();

  // ── Brand palette ────────────────────────────────────────────────────────
  static const navy      = Color(0xFF050F1C);
  static const navyMid   = Color(0xFF0C1E33);
  static const navyLight = Color(0xFF162D47);
  static const teal      = Color(0xFF0891B2);
  static const tealLight = Color(0xFF06B6D4);
  static const tealGlow  = Color(0xFF22D3EE);
  static const offWhite  = Color(0xFFF0F4F8);
  static const surface   = Color(0xFFFFFFFF);

  // ── Card surfaces ────────────────────────────────────────────────────────
  static const cardDark    = Color(0xFF0F2133);
  static const cardLight   = Color(0xFFFFFFFF);
  static const borderDark  = Color(0xFF1E3A54);
  static const borderLight = Color(0xFFE2E8F0);

  // ── Severity / priority ──────────────────────────────────────────────────
  static const critical  = Color(0xFFEF4444);
  static const high      = Color(0xFFF97316);
  static const medium    = Color(0xFFEAB308);
  static const low       = Color(0xFF22C55E);

  // ── Agent / class colours ────────────────────────────────────────────────
  static const d00Color = Color(0xFFF97316);
  static const d10Color = Color(0xFFEAB308);
  static const d20Color = Color(0xFFD946EF);
  static const d40Color = Color(0xFFEF4444);
  static const d50Color = Color(0xFF06B6D4);
  static const d60Color = Color(0xFF22C55E);
  static const d90Color = Color(0xFFF59E0B);

  // ── Status / chrome ──────────────────────────────────────────────────────
  static const mockWarning    = Color(0xFFF97316);
  static const partialWarning = Color(0xFFEF4444);
  static const syncPending    = Color(0xFFF59E0B);
  static const syncDone       = Color(0xFF22C55E);
  static const syncFailed     = Color(0xFFEF4444);

  // ── Text on dark surfaces ────────────────────────────────────────────────
  static const textOnDark       = Color(0xFFF1F5F9);
  static const textSubtleOnDark = Color(0xFF94A3B8);
  static const textFaintOnDark  = Color(0xFF475569);

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

  static Color forPriority(double score) {
    if (score >= 70) return critical;
    if (score >= 40) return high;
    if (score >= 20) return medium;
    return low;
  }
}
