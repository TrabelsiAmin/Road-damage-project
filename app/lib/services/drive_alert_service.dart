import 'package:flutter/services.dart';
import '../models/upcoming_anomaly.dart';

enum AlertSeverity {
  info,
  warning,
  critical,
}

/// Handles gentle audio/haptic alert triggers during driving with cooldown protections.
class DriveAlertService {
  DriveAlertService({
    this.soundEnabled = true,
    this.hapticEnabled = true,
    this.warningDistanceMeters = 180.0,
    this.urgentDistanceMeters = 60.0,
    this.alertCooldown = const Duration(seconds: 40),
  });

  bool soundEnabled;
  bool hapticEnabled;
  final double warningDistanceMeters;
  final double urgentDistanceMeters;
  final Duration alertCooldown;

  final Map<String, DateTime> _lastAlertedTime = {};
  final Set<String> _urgentAlerted = {};

  /// Evaluates an upcoming anomaly result and triggers alerts if appropriate.
  Future<bool> processAlert(UpcomingAnomalyResult result) async {
    if (!result.hasAnomaly || result.distanceMeters == null) {
      return false;
    }

    final anomaly = result.anomaly!;
    final distance = result.distanceMeters!;
    final now = DateTime.now();

    // Check if within warning range
    if (distance > warningDistanceMeters) {
      return false;
    }

    final id = anomaly.observationId;
    final lastTime = _lastAlertedTime[id];
    final isUrgentZone = distance <= urgentDistanceMeters;

    // Determine if we should trigger an alert
    bool shouldTrigger = false;
    AlertSeverity severity = AlertSeverity.info;

    if (lastTime == null) {
      // First time entering warning range
      shouldTrigger = true;
      severity = isUrgentZone || anomaly.isPothole ? AlertSeverity.critical : AlertSeverity.warning;
    } else if (isUrgentZone && !_urgentAlerted.contains(id)) {
      // Escalating from warning to urgent
      shouldTrigger = true;
      severity = AlertSeverity.critical;
      _urgentAlerted.add(id);
    } else if (now.difference(lastTime) > alertCooldown) {
      // Cooldown expired and still approaching
      shouldTrigger = true;
      severity = isUrgentZone ? AlertSeverity.critical : AlertSeverity.warning;
    }

    if (!shouldTrigger) return false;

    _lastAlertedTime[id] = now;
    if (isUrgentZone) {
      _urgentAlerted.add(id);
    }

    await _emitAlert(severity);
    return true;
  }

  Future<void> _emitAlert(AlertSeverity severity) async {
    if (hapticEnabled) {
      switch (severity) {
        case AlertSeverity.critical:
          await HapticFeedback.heavyImpact();
          break;
        case AlertSeverity.warning:
          await HapticFeedback.mediumImpact();
          break;
        case AlertSeverity.info:
          await HapticFeedback.lightImpact();
          break;
      }
    }

    if (soundEnabled) {
      await SystemSound.play(SystemSoundType.alert);
    }
  }

  /// Clears alert cooldown histories.
  void reset() {
    _lastAlertedTime.clear();
    _urgentAlerted.clear();
  }
}
