import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/observation.dart';

/// Saved synchronisation preferences. Read at each sync attempt.
class SyncSettings {
  const SyncSettings({
    required this.wifiOnly,
    required this.retentionDays,
  });

  /// When true, uploads run only on Wi-Fi.
  final bool wifiOnly;

  /// Days a fully synced local photo is kept. Zero means keep forever.
  final int retentionDays;

  static const wifiOnlyKey = 'wifi_only';
  static const retentionDaysKey = 'retention_days';

  static SyncSettings fromPrefs(SharedPreferences prefs) {
    return SyncSettings(
      wifiOnly: prefs.getBool(wifiOnlyKey) ?? true,
      retentionDays: prefs.getInt(retentionDaysKey) ?? 90,
    );
  }

  Future<void> write(SharedPreferences prefs) async {
    await prefs.setBool(wifiOnlyKey, wifiOnly);
    await prefs.setInt(retentionDaysKey, retentionDays);
  }
}

typedef SyncSettingsReader = Future<SyncSettings> Function();
typedef SyncNetworkReader = Future<SyncNetworkType> Function();

/// Prefs that cannot be read do not delete photos and do not assume mobile data is allowed.
Future<SyncSettings> readStoredSyncSettings() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return SyncSettings.fromPrefs(prefs);
  } catch (_) {
    return const SyncSettings(wifiOnly: true, retentionDays: 0);
  }
}

enum SyncNetworkType { wifi, mobile, unknown }

enum SyncTransportDecision { allowed, blocked }

const String wifiOnlyBlockedMessage =
    'Wi-Fi-only mode blocked this upload. Connect to Wi-Fi, or turn off Wi-Fi-only uploads in Settings.';

/// A stored original URL can be read when the radio is Wi-Fi or mobile.
/// Unknown includes offline and is not queried.
bool remoteUrlRecoveryMayQuery(SyncNetworkType network) {
  return network == SyncNetworkType.wifi || network == SyncNetworkType.mobile;
}

/// Wi-Fi-only off keeps the previous behavior: no extra network requirement.
/// An unknown type is not treated as Wi-Fi.
SyncTransportDecision decideSyncTransport({
  required bool wifiOnly,
  required SyncNetworkType network,
}) {
  if (!wifiOnly) return SyncTransportDecision.allowed;
  if (network == SyncNetworkType.wifi) return SyncTransportDecision.allowed;
  return SyncTransportDecision.blocked;
}

SyncNetworkType syncNetworkTypeFromNames(Iterable<String> names) {
  final values = names.map((name) => name.toLowerCase()).toSet();
  if (values.contains('wifi')) return SyncNetworkType.wifi;
  if (values.contains('mobile')) return SyncNetworkType.mobile;
  return SyncNetworkType.unknown;
}

Future<SyncNetworkType> readDeviceSyncNetwork() async {
  try {
    final results = await Connectivity().checkConnectivity();
    return syncNetworkTypeFromNames(results.map((result) => result.name));
  } catch (_) {
    return SyncNetworkType.unknown;
  }
}

/// A local photo may be removed only after a full sync and the retention window.
bool localPhotoIsEligibleForDeletion({
  required SyncStatus syncStatus,
  required MediaSyncStatus mediaSyncStatus,
  required DateTime createdAt,
  required DateTime now,
  required int retentionDays,
}) {
  if (retentionDays <= 0) return false;
  if (syncStatus != SyncStatus.synced) return false;
  if (mediaSyncStatus != MediaSyncStatus.uploaded) return false;
  final cutoff = now.toUtc().subtract(Duration(days: retentionDays));
  return !createdAt.toUtc().isAfter(cutoff);
}

/// Paths that are safe to delete. A path shared with a row that still needs
/// its file, including retry, is kept.
List<String> localPhotoPathsToDelete({
  required List<Observation> observations,
  required int retentionDays,
  required DateTime now,
}) {
  bool eligible(Observation obs) => localPhotoIsEligibleForDeletion(
        syncStatus: obs.syncStatus,
        mediaSyncStatus: obs.mediaSyncStatus,
        createdAt: obs.createdAt,
        now: now,
        retentionDays: retentionDays,
      );

  final keep = <String>{};
  for (final obs in observations) {
    if (eligible(obs)) continue;
    if (obs.imagePath.isNotEmpty) keep.add(obs.imagePath);
    final annotated = obs.annotatedImagePath;
    if (annotated != null && annotated.isNotEmpty) keep.add(annotated);
  }

  final paths = <String>[];
  final seen = <String>{};
  for (final obs in observations) {
    if (!eligible(obs)) continue;
    for (final path in [obs.imagePath, obs.annotatedImagePath]) {
      if (path == null || path.isEmpty) continue;
      if (keep.contains(path) || seen.contains(path)) continue;
      seen.add(path);
      paths.add(path);
    }
  }
  return paths;
}

/// Deletes only regular files from [localPhotoPathsToDelete]. Directories and
/// missing files are left alone. Database rows are not deleted.
Future<int> deleteEligibleLocalPhotos({
  required List<Observation> observations,
  required int retentionDays,
  required DateTime now,
}) async {
  var deleted = 0;
  for (final path in localPhotoPathsToDelete(
    observations: observations,
    retentionDays: retentionDays,
    now: now,
  )) {
    try {
      final type = await FileSystemEntity.type(path, followLinks: false);
      if (type != FileSystemEntityType.file) continue;
      await File(path).delete();
      deleted++;
    } catch (_) {}
  }
  return deleted;
}
