import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../core/app_colors.dart';

/// Full-screen camera view with plain preview only.
///
/// Capture returns the photo path and does not run detection or save an
/// observation. The caller shows the confirm screen before anything is stored.
class CameraDetectionScreen extends StatefulWidget {
  const CameraDetectionScreen({super.key});

  @override
  State<CameraDetectionScreen> createState() => _CameraDetectionScreenState();
}

class _CameraDetectionScreenState extends State<CameraDetectionScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _initialized = false;
  bool _analyzing = false;
  bool _cameraStarting = true;
  String? _cameraError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  Future<void> _initCamera() async {
    if (mounted) {
      setState(() {
        _cameraError = null;
        _cameraStarting = true;
        _initialized = false;
      });
    }
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _cameraError = 'No camera is available on this device.';
            _cameraStarting = false;
          });
        }
        return;
      }
      await _startCamera(_cameras.first);
      if (mounted) setState(() => _cameraStarting = false);
    } catch (e) {
      debugPrint('[Camera] Init error: $e');
      if (mounted) {
        setState(() {
          _cameraError = 'Camera could not start. Check permission and try again.';
          _cameraStarting = false;
          _initialized = false;
        });
      }
    }
  }

  Future<void> _startCamera(CameraDescription desc) async {
    final controller = CameraController(
      desc,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    await controller.initialize();
    if (!mounted) return;
    setState(() {
      _controller = controller;
      _initialized = true;
    });
  }

  Future<void> _capture() async {
    if (_analyzing || _controller == null || !_controller!.value.isInitialized) {
      return;
    }
    setState(() => _analyzing = true);

    try {
      final photo = await _controller!.takePicture();
      if (!mounted) return;
      Navigator.of(context).pop(photo.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture failed: $e'), backgroundColor: AppColors.critical),
        );
        setState(() => _analyzing = false);
      }
    }
  }

  void _switchCamera() async {
    if (_cameras.length < 2 || _analyzing) return;
    final current = _controller?.description;
    final next = _cameras.firstWhere(
      (c) => c != current,
      orElse: () => _cameras.first,
    );
    await _controller?.dispose();
    setState(() {
      _controller = null;
      _initialized = false;
      _cameraError = null;
    });
    try {
      await _startCamera(next);
    } catch (e) {
      debugPrint('[Camera] Switch error: $e');
      if (mounted) {
        setState(() {
          _cameraError = 'Camera could not start. Check permission and try again.';
          _initialized = false;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null) return;
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Camera plain preview ────────────────────────────────
          if (_initialized && _controller != null && _cameraError == null)
            CameraPreview(_controller!)
          else if (_cameraError != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.videocam_off_outlined, color: Colors.white70, size: 36),
                    const SizedBox(height: 12),
                    Text(
                      _cameraError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _cameraStarting ? null : _initCamera,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          else
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text('Initialising camera…', style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),

          // ── Top bar ─────────────────────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _analyzing ? null : () => Navigator.of(context).pop(),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Camera',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Bottom controls ──────────────────────────────────────
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Switch camera
                    _ControlButton(
                      icon: Icons.flip_camera_android_outlined,
                      label: 'Flip',
                      onTap: (_cameras.length > 1 && !_analyzing) ? _switchCamera : null,
                    ),
                    // Shutter button
                    Semantics(
                      button: true,
                      label: 'Take photo',
                      child: GestureDetector(
                      onTap: _analyzing ? null : _capture,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: _analyzing ? 68 : 74,
                        height: _analyzing ? 68 : 74,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _analyzing ? Colors.grey : Colors.white,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(color: Colors.white.withAlpha(80), blurRadius: 16),
                          ],
                        ),
                        child: _analyzing
                            ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.teal))
                            : const Icon(Icons.camera, color: Colors.black, size: 32),
                      ),
                    ),
                    ),
                    const _ControlButton(icon: Icons.info_outline, label: 'Info', onTap: null),
                  ],
                ),
              ),
            ),
          ),

          // ── Analyzing overlay state (CHANGE 1) ────────────────────
          if (_analyzing)
            Positioned.fill(
              child: Container(
                color: Colors.black.withAlpha(180),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(100),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: AppColors.teal, strokeWidth: 3),
                        SizedBox(height: 18),
                        Text(
                          'Taking the photo…',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Detection starts after you confirm.',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
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

class _ControlButton extends StatelessWidget {
  const _ControlButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: onTap != null ? Colors.black45 : Colors.black26,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: onTap != null ? Colors.white : Colors.white38, size: 22),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: onTap != null ? Colors.white70 : Colors.white30, fontSize: 10)),
      ],
    ),
  );
}
