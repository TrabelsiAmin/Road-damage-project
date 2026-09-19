import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/observation.dart';
import '../core/app_colors.dart';
import '../core/constants.dart';

// ---------------------------------------------------------------------------
// Painter
// ---------------------------------------------------------------------------

class _BoxPainter extends CustomPainter {
  _BoxPainter(this.detections, this.imageSize, this.highlightedIndex);
  final List<Detection> detections;
  final Size imageSize;
  final int? highlightedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / imageSize.width;
    final scaleY = size.height / imageSize.height;

    for (var i = 0; i < detections.length; i++) {
      final d = detections[i];
      final color = AppColors.forClassCode(d.classCode);
      final b = d.box;
      final isHighlighted = highlightedIndex == i;

      final rect = Rect.fromLTWH(
        b.x * imageSize.width * scaleX,
        b.y * imageSize.height * scaleY,
        b.width * imageSize.width * scaleX,
        b.height * imageSize.height * scaleY,
      );

      // Glow / highlight fill
      canvas.drawRect(
        rect.inflate(isHighlighted ? 6 : 3),
        Paint()
          ..color = color.withAlpha(isHighlighted ? 90 : 50)
          ..style = PaintingStyle.fill,
      );

      // Box border
      canvas.drawRect(
        rect,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = isHighlighted ? 3.5 : 2.5,
      );

      // Label pill
      final label = '${TariqMapConstants.labelFor(d.classCode)}  ${(d.confidence * 100).toStringAsFixed(0)}%';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      const padding = 4.0;
      final pillY = rect.top - tp.height - padding * 2;
      final pillRect = Rect.fromLTWH(
        rect.left,
        pillY.clamp(0.0, size.height - tp.height - padding * 2),
        tp.width + padding * 2,
        tp.height + padding * 2,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(pillRect, const Radius.circular(4)),
        Paint()..color = color,
      );
      tp.paint(canvas, Offset(pillRect.left + padding, pillRect.top + padding));

      // Index badge (small circle) for tappable cards
      final badgeCenter = Offset(rect.right - 8, rect.top + 8);
      canvas.drawCircle(badgeCenter, 10, Paint()..color = color);
      final badgeTp = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      badgeTp.paint(canvas, badgeCenter - Offset(badgeTp.width / 2, badgeTp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_BoxPainter old) =>
      old.detections != detections || old.highlightedIndex != highlightedIndex;
}

// ---------------------------------------------------------------------------
// Public widget
// ---------------------------------------------------------------------------

class AnnotatedImageWidget extends StatefulWidget {
  const AnnotatedImageWidget({
    super.key,
    required this.imagePath,
    required this.detections,
    this.highlightedIndex,
  });

  final String imagePath;
  final List<Detection> detections;

  /// When non-null, the box at this index receives a glow highlight.
  final int? highlightedIndex;

  @override
  State<AnnotatedImageWidget> createState() => _AnnotatedImageWidgetState();
}

class _AnnotatedImageWidgetState extends State<AnnotatedImageWidget> {
  ImageInfo? _info;
  ImageStream? _stream;
  late ImageStreamListener _listener;

  @override
  void initState() {
    super.initState();
    // Intentionally empty: _resolveImage needs MediaQuery (via
    // createLocalImageConfiguration) which is only available from
    // didChangeDependencies onward, not during initState.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = kIsWeb
        ? NetworkImage(widget.imagePath) as ImageProvider
        : FileImage(File(widget.imagePath));
    _resolveImage(provider);
  }

  void _resolveImage(ImageProvider provider) {
    _stream?.removeListener(_listener);
    _stream = provider.resolve(createLocalImageConfiguration(context));
    _listener = ImageStreamListener((info, _) {
      if (mounted) setState(() => _info = info);
    });
    _stream!.addListener(_listener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imageWidget = kIsWeb
        ? Image.network(widget.imagePath, fit: BoxFit.contain)
        : Image.file(File(widget.imagePath), fit: BoxFit.contain);

    final naturalSize = _info == null
        ? null
        : Size(_info!.image.width.toDouble(), _info!.image.height.toDouble());

    return Stack(
      fit: StackFit.passthrough,
      children: [
        imageWidget,
        if (naturalSize != null)
          Positioned.fill(
            child: CustomPaint(
              painter: _BoxPainter(widget.detections, naturalSize, widget.highlightedIndex),
            ),
          ),
        if (naturalSize == null)
          const Positioned.fill(
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
      ],
    );
  }
}
