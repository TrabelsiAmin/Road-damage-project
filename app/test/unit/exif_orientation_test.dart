import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tariqmap/inference/preprocessing.dart';

void main() {
  Uint8List jpegWithOrientation(int? orientation,
      {int width = 8, int height = 4}) {
    final image = img.Image(width: width, height: height);
    image.clear(img.ColorRgb8(10, 20, 30));
    if (orientation != null) {
      image.exif.imageIfd.orientation = orientation;
    }
    return Uint8List.fromList(img.encodeJpg(image, quality: 95));
  }

  test('orientation 1 is not re-encoded', () {
    final bytes = jpegWithOrientation(1);
    final prepared = bytesForUpload(bytes);
    expect(identical(prepared, bytes), isTrue);
  });

  test(
      'orientations 3, 6 and 8 bake once and malformed metadata stays decodable',
      () {
    final upright = decodeAndOrient(jpegWithOrientation(1));
    expect(upright.width, 8);
    expect(upright.height, 4);

    final turned = decodeAndOrient(jpegWithOrientation(6));
    expect(turned.width, 4);
    expect(turned.height, 8);

    final turnedOther = decodeAndOrient(jpegWithOrientation(8));
    expect(turnedOther.width, 4);
    expect(turnedOther.height, 8);

    final spun = decodeAndOrient(jpegWithOrientation(3));
    expect(spun.width, 8);
    expect(spun.height, 4);

    final plain = img.Image(width: 3, height: 2);
    expect(orientDecodedImage(plain).width, 3);

    final broken = img.Image(width: 3, height: 2);
    expect(orientDecodedImage(broken).height, 2);
  });

  test('portrait and landscape orientations bake once and keep a corner pixel',
      () {
    img.Image marked(int width, int height, int? orientation) {
      final image = img.Image(width: width, height: height);
      image.clear(img.ColorRgb8(10, 20, 30));
      image.setPixelRgb(0, 0, 255, 0, 0);
      if (orientation != null) image.exif.imageIfd.orientation = orientation;
      return image;
    }

    final landscape =
        decodeAndOrient(Uint8List.fromList(img.encodeJpg(marked(8, 4, 6))));
    expect(landscape.width, 4);
    expect(landscape.height, 8);
    final again = orientDecodedImage(landscape);
    expect(again.width, landscape.width);
    expect(again.height, landscape.height);

    final portrait =
        decodeAndOrient(Uint8List.fromList(img.encodeJpg(marked(4, 8, 6))));
    expect(portrait.width, 8);
    expect(portrait.height, 4);

    final missing = jpegWithOrientation(null, width: 8, height: 4);
    expect(identical(bytesForUpload(missing), missing), isTrue);

    final invalid = marked(8, 4, 99);
    final invalidBytes = Uint8List.fromList(img.encodeJpg(invalid));
    expect(identical(bytesForUpload(invalidBytes), invalidBytes), isTrue);
    expect(decodeAndOrient(invalidBytes).width, 8);
  });

  test('stretch is still 640 after orientation', () {
    final oriented =
        decodeAndOrient(jpegWithOrientation(6, width: 20, height: 10));
    final stretched = stretchToModelInput(oriented);
    expect(stretched.width, 640);
    expect(stretched.height, 640);
  });

  test('corrupted bytes are not rewritten and a large photo is oriented once',
      () {
    final corrupted = Uint8List.fromList([0x00, 0x11, 0x22, 0x33, 0xff]);
    expect(identical(bytesForUpload(corrupted), corrupted), isTrue);
    expect(() => decodeAndOrient(corrupted), throwsArgumentError);

    final large = jpegWithOrientation(6, width: 1280, height: 720);
    final oriented = decodeAndOrient(large);
    expect(oriented.width, 720);
    expect(oriented.height, 1280);
    final second = orientDecodedImage(oriented);
    expect(second.width, 720);
    expect(second.height, 1280);
    final stretched = stretchToModelInput(oriented);
    expect(stretched.width, 640);
    expect(stretched.height, 640);
    final upright = jpegWithOrientation(1, width: 640, height: 480);
    expect(identical(bytesForUpload(upright), upright), isTrue);
  });
}
