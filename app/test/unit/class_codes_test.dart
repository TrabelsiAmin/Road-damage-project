import 'package:flutter_test/flutter_test.dart';
import 'package:tariqmap/core/class_codes.dart';

void main() {
  test('null and blank codes are unknown and are not counted as D40', () {
    expect(displayClassCode(null), 'Unknown class');
    expect(displayClassCode('  '), 'Unknown class');
    expect(statClassCode(null), isNull);
    expect(statClassCode(''), isNull);
    expect(statClassCode(null), isNot('D40'));
  });

  test('an unrecognized code is unknown and is not rewritten to D40', () {
    expect(displayClassCode('D99'), 'Unknown class');
    expect(statClassCode('D99'), isNull);
    expect(isKnownClassCode('D99'), isFalse);
  });

  test('stored D00 D10 D20 and D40 stay those codes', () {
    for (final code in ['D00', 'D10', 'D20', 'D40']) {
      expect(displayClassCode(' $code '), code);
      expect(statClassCode(code), code);
    }
  });
}
