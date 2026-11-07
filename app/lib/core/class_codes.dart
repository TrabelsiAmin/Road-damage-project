/// Stored class ids for the default Android model.
///
/// Missing or unrecognized codes are not rewritten to D40 and are not given
/// a new plain-language name. Historical rows are left as stored.
const knownClassCodes = <String>{'D00', 'D10', 'D20', 'D40'};

const unknownClassLabel = 'Unknown class';

String? rawClassCode(String? value) {
  if (value == null) return null;
  final text = value.trim();
  if (text.isEmpty) return null;
  return text;
}

bool isKnownClassCode(String? value) => knownClassCodes.contains(rawClassCode(value));

/// Heading shown in the UI. Known codes stay D00–D40.
String displayClassCode(String? value) {
  final code = rawClassCode(value);
  if (!isKnownClassCode(code)) return unknownClassLabel;
  return code!;
}

/// Null when a count must not include this detection in a class bucket.
String? statClassCode(String? value) {
  final code = rawClassCode(value);
  if (!isKnownClassCode(code)) return null;
  return code;
}
