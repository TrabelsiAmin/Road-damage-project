import os
import re

def main():
    base = "c:/manus/TariqMap/app"
    
    # 1. observation_dao.dart
    p = os.path.join(base, "lib/data/local/observation_dao.dart")
    if os.path.exists(p):
        with open(p, 'r', encoding='utf-8') as f:
            c = f.read()
        if "package:sqflite/sqflite.dart" not in c:
            c = c.replace("import '../../models/observation.dart';", 
                          "import 'package:sqflite/sqflite.dart';\nimport '../../models/observation.dart';")
            with open(p, 'w', encoding='utf-8') as f:
                f.write(c)

    # 2. annotation_renderer.dart
    p = os.path.join(base, "lib/inference/annotation_renderer.dart")
    if os.path.exists(p):
        with open(p, 'r', encoding='utf-8') as f:
            c = f.read()
        # Fix num vs int for toPixels returns
        c = re.sub(r'final \(x, y, w, h\) = d\.box\.toPixels\(origW, origH\);', 
                   r'final (nx, ny, nw, nh) = d.box.toPixels(origW, origH);\n    final x = nx.toInt();\n    final y = ny.toInt();\n    final w = nw.toInt();\n    final h = nh.toInt();', c)
        
        # Fix deprecated .red, .green, .blue
        c = c.replace("c.red", "(c.r * 255.0).round().clamp(0, 255)")
        c = c.replace("c.green", "(c.g * 255.0).round().clamp(0, 255)")
        c = c.replace("c.blue", "(c.b * 255.0).round().clamp(0, 255)")
        with open(p, 'w', encoding='utf-8') as f:
            f.write(c)

    # 3. temporal_smoothing.dart
    p = os.path.join(base, "lib/inference/temporal_smoothing.dart")
    if os.path.exists(p):
        with open(p, 'r', encoding='utf-8') as f:
            c = f.read()
        c = re.sub(r'smoothedConfidence: d\.confidence,\n\s+', '', c)
        with open(p, 'w', encoding='utf-8') as f:
            f.write(c)

    # 4. annotated_image.dart
    p = os.path.join(base, "lib/widgets/annotated_image.dart")
    if os.path.exists(p):
        with open(p, 'r', encoding='utf-8') as f:
            c = f.read()
        c = c.replace("import '../screens/camera_detection_screen.dart' show classColor, classLabel;", 
                      "import '../core/app_colors.dart';\nimport '../core/constants.dart';")
        c = c.replace("final color = classColor(d.classCode);", 
                      "final color = AppColors.forClassCode(d.classCode);")
        c = c.replace("classLabel(d.classCode)", "TariqMapConstants.labelFor(d.classCode)")
        with open(p, 'w', encoding='utf-8') as f:
            f.write(c)
            
    # 5. _agentDefs missing import in detection_service.dart ? Wait, constants.dart might be needed if they used TariqMapConstants?
    # No, unused import constants.dart was there.

    print("Fixes applied.")

if __name__ == "__main__":
    main()
