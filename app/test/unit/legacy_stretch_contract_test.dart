import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tariqmap/inference/preprocessing.dart';

void main() {
  test('legacy stretch fills 640x640 and does not insert gray-114 bars', () {
    final src = img.Image(width: 640, height: 480);
    src.clear(img.ColorRgb8(10, 20, 30));

    final stretched = stretchToModelInput(src, inputSize: 640);
    expect(stretched.width, 640);
    expect(stretched.height, 640);
    // Top row is image content. Letterbox would put gray 114 in the bar.
    final top = stretched.getPixel(320, 0);
    expect(top.r.toInt(), 10);
    expect(top.g.toInt(), 20);
    expect(top.b.toInt(), 30);

    final letter = letterboxProcess(src, inputSize: 640);
    expect(letter.padX, 0);
    expect(letter.padY, isNot(0));
    expect(letter.newWidth, 640);
    expect(letter.newHeight, 480);
    expect(letter.image.getPixel(320, 0).r.toInt(), 114);
    expect(letter.image.getPixel(320, 0).g.toInt(), 114);
    expect(letter.image.getPixel(320, 0).b.toInt(), 114);
  });

  test('legacy stretch keeps a uniform portrait color in all four corners', () {
    final src = img.Image(width: 480, height: 640);
    src.clear(img.ColorRgb8(9, 8, 7));

    final stretched = stretchToModelInput(src);
    expect(stretched.width, 640);
    expect(stretched.height, 640);
    for (final point in const [(0, 0), (639, 0), (0, 639), (639, 639)]) {
      final px = stretched.getPixel(point.$1, point.$2);
      expect(px.r.toInt(), 9, reason: 'corner $point');
      expect(px.g.toInt(), 8, reason: 'corner $point');
      expect(px.b.toInt(), 7, reason: 'corner $point');
    }
  });
}
