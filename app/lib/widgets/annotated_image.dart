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
      old.detections != detections || old.highlightedIndex != highlightedIndex || old.imageSize != imageSize;
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
  bool _hasError = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadImage();
  }

  @override
  void didUpdateWidget(AnnotatedImageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath) {
      _loadImage();
    }
  }

  void _loadImage() {
    final provider = kIsWeb
        ? NetworkImage(widget.imagePath) as ImageProvider
        : FileImage(File(widget.imagePath));

    _stream?.removeListener(_listener);
    _stream = provider.resolve(createLocalImageConfiguration(context));
    
    _listener = ImageStreamListener(
      (info, _) {
        if (mounted) setState(() {
          _info = info;
          _hasError = false;
        });
      },
      onError: (exception, stackTrace) {
        debugPrint('[AnnotatedImage] Failed to load image: $exception');
        if (mounted) setState(() => _hasError = true);
      },
    );
    _stream!.addListener(_listener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_rounded, color: Colors.white54, size: 48),
            SizedBox(height: 8),
            Text('Failed to load image', style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }

    if (_info == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.teal));
    }

    final naturalSize = Size(_info!.image.width.toDouble(), _info!.image.height.toDouble());
    final rawImage = kIsWeb
        ? Image.network(widget.imagePath, width: naturalSize.width, height: naturalSize.height, fit: BoxFit.fill)
        : Image.file(File(widget.imagePath), width: naturalSize.width, height: naturalSize.height, fit: BoxFit.fill);

    // Using FittedBox ensures that the Stack (which is exactly the size of the 
    // original image) is scaled down as a single unit. This guarantees that the 
    // bounding boxes perfectly align with the pixels of the image, regardless of 
    // whether the parent uses BoxFit.contain or BoxFit.cover!
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: naturalSize.width,
          height: naturalSize.height,
          child: Stack(
            children: [
              rawImage,
              Positioned.fill(
                child: CustomPaint(
                  painter: _BoxPainter(widget.detections, naturalSize, widget.highlightedIndex),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
