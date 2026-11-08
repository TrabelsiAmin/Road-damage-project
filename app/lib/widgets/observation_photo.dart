import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/observation.dart';

/// How a saved observation should show its photo.
enum PhotoSourceKind {
  /// The local file is still on this device.
  localAvailable,

  /// Retention removed the local file. A stored remote URL remains.
  remoteAvailable,

  /// Fully synced, but neither a local file nor a remote URL is available.
  unavailable,

  /// The upload has not finished. The local file is gone, so it cannot be shown.
  uploadIncomplete,
}

class PhotoSource {
  const PhotoSource({
    required this.kind,
    this.localPath,
    this.remoteUrl,
  });

  final PhotoSourceKind kind;
  final String? localPath;
  final String? remoteUrl;

  String get label => switch (kind) {
        PhotoSourceKind.localAvailable => 'Local photo',
        PhotoSourceKind.remoteAvailable => 'Remote photo',
        PhotoSourceKind.unavailable => 'Photo unavailable',
        PhotoSourceKind.uploadIncomplete => 'Photo upload incomplete',
      };
}

/// Local file wins. A remote URL is used only after a full sync.
/// An incomplete upload is never presented as a remote photo.
PhotoSource resolvePhotoSource({
  required bool localFileExists,
  required String? remoteImageUrl,
  required SyncStatus syncStatus,
  required MediaSyncStatus mediaSyncStatus,
}) {
  final url = remoteImageUrl?.trim();
  final remote = url != null && url.isNotEmpty ? url : null;
  if (localFileExists) {
    return PhotoSource(kind: PhotoSourceKind.localAvailable, remoteUrl: remote);
  }
  final fullySynced = syncStatus == SyncStatus.synced &&
      mediaSyncStatus == MediaSyncStatus.uploaded;
  if (!fullySynced) {
    return PhotoSource(
      kind: PhotoSourceKind.uploadIncomplete,
      remoteUrl: remote,
    );
  }
  if (remote != null) {
    return PhotoSource(kind: PhotoSourceKind.remoteAvailable, remoteUrl: remote);
  }
  return const PhotoSource(kind: PhotoSourceKind.unavailable);
}

/// History, queue, and result thumbnails. A missing file is a labeled state,
/// not an empty image.
class ObservationPhoto extends StatelessWidget {
  const ObservationPhoto({
    super.key,
    required this.observation,
    this.fit = BoxFit.cover,
    this.localFileExists,
  });

  final Observation observation;
  final BoxFit fit;

  /// Test seam. Production checks the local file.
  final bool? localFileExists;

  @override
  Widget build(BuildContext context) {
    final exists = localFileExists ?? _fileExists(observation.imagePath);
    final source = resolvePhotoSource(
      localFileExists: exists,
      remoteImageUrl: observation.remoteImageUrl,
      syncStatus: observation.syncStatus,
      mediaSyncStatus: observation.mediaSyncStatus,
    );
    return Semantics(
      label: source.label,
      child: switch (source.kind) {
        PhotoSourceKind.localAvailable => Image.file(
            File(observation.imagePath),
            fit: fit,
            errorBuilder: (_, __, ___) => _notice(
              'Photo unavailable',
              Icons.image_not_supported_outlined,
            ),
          ),
        PhotoSourceKind.remoteAvailable => _RemotePhoto(
            url: source.remoteUrl!,
            fit: fit,
          ),
        PhotoSourceKind.unavailable => _notice(
            'Photo unavailable',
            Icons.image_not_supported_outlined,
          ),
        PhotoSourceKind.uploadIncomplete => _notice(
            'Photo upload incomplete',
            Icons.cloud_off_rounded,
          ),
      },
    );
  }

  static bool _fileExists(String path) {
    if (kIsWeb || path.isEmpty) return false;
    return File(path).existsSync();
  }
}

class _RemotePhoto extends StatefulWidget {
  const _RemotePhoto({required this.url, required this.fit});

  final String url;
  final BoxFit fit;

  @override
  State<_RemotePhoto> createState() => _RemotePhotoState();
}

class _RemotePhotoState extends State<_RemotePhoto> {
  bool _offline = false;

  @override
  Widget build(BuildContext context) {
    if (_offline) {
      return _notice('Photo offline', Icons.wifi_off_rounded);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.network(
          widget.url,
          fit: widget.fit,
          errorBuilder: (_, __, ___) {
            if (!_offline) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _offline = true);
              });
            }
            return _notice('Photo offline', Icons.wifi_off_rounded);
          },
        ),
        const Positioned(
          left: 4,
          right: 4,
          bottom: 4,
          child: _PhotoLabel('Remote photo'),
        ),
      ],
    );
  }
}

class _PhotoLabel extends StatelessWidget {
  const _PhotoLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xCC122033),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(
          text,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

Widget _notice(String label, IconData icon) {
  return ColoredBox(
    color: const Color(0xFF1C2430),
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 120),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white70, size: 18),
              const SizedBox(height: 2),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
