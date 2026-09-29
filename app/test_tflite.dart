import "dart:typed_data";
import "package:tflite_flutter/tflite_flutter.dart";
void main() {
  var flat = Float32List(12);
  var reshaped = flat.reshape([1, 3, 4]);
  print("Reshaped type: ${reshaped.runtimeType}");
  
  // Simulate what tflite_flutter does internally to output buffers
  if (reshaped is List) {
    reshaped[0][0][0] = 99.0;
  }
  
  print("Flat value: ${flat[0]}");
}
