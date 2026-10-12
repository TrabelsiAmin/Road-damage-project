"""
Export Golden Data for RoadSense TFLite Model.

Runs roadsense_best.tflite on 5 test images with letterbox preprocessing [1, 3, 640, 640] NCHW,
extracts preprocessed tensor stats, raw output tensor, and decoded detections (both pre-NMS and post-NMS),
and saves everything to app/test/goldens/roadsense_goldens.json and copies test images to app/test/goldens/images/.
"""
import json
import shutil
from pathlib import Path
import cv2
import numpy as np
import ai_edge_litert.interpreter as tflite

# Configuration
MODEL_PATH = Path("roadsense_best.tflite")
IMAGES_DIR = Path("archive (3)/RDD_SPLIT/test/images")
GOLDEN_DIR = Path("app/test/goldens")
GOLDEN_IMAGES_DIR = GOLDEN_DIR / "images"
GOLDEN_JSON = GOLDEN_DIR / "roadsense_goldens.json"

GOLDEN_DIR.mkdir(parents=True, exist_ok=True)
GOLDEN_IMAGES_DIR.mkdir(parents=True, exist_ok=True)

# Select 5 diverse images (square and non-square)
IMAGE_NAMES = [
    "China_Drone_000017.jpg",  # 512x512, D00, D10
    "China_Drone_000273.jpg",  # 512x512, strong D20 (alligator crack)
    "China_Drone_000085.jpg",  # 512x512, D10
    "Norway_000001.jpg",        # 3643x2041 (rectangular aspect ratio)
    "Czech_000010.jpg",         # 600x600 (street-level)
]

CLASS_NAMES = {
    0: "D00",
    1: "D10",
    2: "D20",
    3: "D40",
    4: "Repair",
}

CLASS_THRESHOLDS = {
    "D00": 0.35,
    "D10": 0.35,
    "D20": 0.30,
    "Repair": 0.25,
}

def box_iou(b1, b2):
    """b1, b2 are [x1, y1, x2, y2]."""
    x1 = max(b1[0], b2[0])
    y1 = max(b1[1], b2[1])
    x2 = min(b1[2], b2[2])
    y2 = min(b1[3], b2[3])
    inter = max(0.0, x2 - x1) * max(0.0, y2 - y1)
    a1 = (b1[2] - b1[0]) * (b1[3] - b1[1])
    a2 = (b2[2] - b2[0]) * (b2[3] - b2[1])
    union = a1 + a2 - inter
    return inter / union if union > 0 else 0.0

def class_aware_nms(dets, iou_thresh=0.45):
    """Performs class-wise NMS matching TariqMap nms.dart."""
    by_class = {}
    for d in dets:
        c = d["classCode"]
        by_class.setdefault(c, []).append(d)

    result = []
    for c, items in by_class.items():
        # Sort descending by confidence
        sorted_items = sorted(items, key=lambda x: x["confidence"], reverse=True)
        kept = []
        for item in sorted_items:
            box = item["box"]
            x1, y1 = box["x"], box["y"]
            x2, y2 = x1 + box["width"], y1 + box["height"]
            b1 = [x1, y1, x2, y2]
            suppressed = False
            for k in kept:
                k_box = k["box"]
                kx1, ky1 = k_box["x"], k_box["y"]
                kx2, ky2 = kx1 + k_box["width"], ky1 + k_box["height"]
                b2 = [kx1, ky1, kx2, ky2]
                if box_iou(b1, b2) > iou_thresh:
                    suppressed = True
                    break
            if not suppressed:
                kept.append(item)
        result.extend(kept)

    # Sort final result descending by confidence
    return sorted(result, key=lambda x: x["confidence"], reverse=True)

def main():
    print(f"Loading model: {MODEL_PATH}")
    interp = tflite.Interpreter(model_path=str(MODEL_PATH))
    interp.allocate_tensors()
    in_det = interp.get_input_details()[0]
    out_det = interp.get_output_details()[0]

    print(f"Input shape: {in_det['shape']}, Output shape: {out_det['shape']}")
    golden_records = []

    for img_name in IMAGE_NAMES:
        img_src = IMAGES_DIR / img_name
        if not img_src.exists():
            raise FileNotFoundError(f"Missing {img_src}")

        # Copy to golden images directory
        dest_img = GOLDEN_IMAGES_DIR / img_name
        shutil.copyfile(img_src, dest_img)

        img_bgr = cv2.imread(str(img_src))
        orig_h, orig_w = img_bgr.shape[:2]

        # 1. Letterbox Preprocessing (Ultralytics spec)
        scale = 640.0 / max(orig_h, orig_w)
        new_w = int(round(orig_w * scale))
        new_h = int(round(orig_h * scale))
        pad_x = (640 - new_w) // 2
        pad_y = (640 - new_h) // 2

        resized = cv2.resize(img_bgr, (new_w, new_h), interpolation=cv2.INTER_LINEAR)
        canvas = np.full((640, 640, 3), 114, dtype=np.uint8)
        canvas[pad_y:pad_y + new_h, pad_x:pad_x + new_w] = resized

        # 2. RGB, Normalize [0..1], NCHW [1, 3, 640, 640]
        rgb = cv2.cvtColor(canvas, cv2.COLOR_BGR2RGB)
        norm_chw = (rgb.astype(np.float32) / 255.0).transpose(2, 0, 1)  # [3, 640, 640]
        input_tensor = norm_chw[np.newaxis, ...]  # [1, 3, 640, 640]

        # Collect tensor sample checks
        tensor_sample = {
            "pad_pixel_rgb": [float(norm_chw[c, 0, 0]) for c in range(3)],
            "center_pixel_rgb": [float(norm_chw[c, 320, 320]) for c in range(3)],
            "mean": float(norm_chw.mean()),
            "min": float(norm_chw.min()),
            "max": float(norm_chw.max()),
            # First 5 values of each channel
            "ch0_first5": [float(x) for x in norm_chw[0, 0, :5]],
            "ch1_first5": [float(x) for x in norm_chw[1, 0, :5]],
            "ch2_first5": [float(x) for x in norm_chw[2, 0, :5]],
        }

        # 3. Inference
        interp.set_tensor(in_det['index'], input_tensor)
        interp.invoke()
        output_tensor = interp.get_tensor(out_det['index'])[0]  # [9, 8400]

        # 4. Decode
        num_anchors = output_tensor.shape[1]  # 8400
        raw_candidates = []
        repair_candidates = []

        for anchor in range(num_anchors):
            # Find best class among classes 0..4
            scores = output_tensor[4:9, anchor]
            best_cls = int(np.argmax(scores))
            best_score = float(scores[best_cls])
            cls_name = CLASS_NAMES[best_cls]

            # Raw coords in letterbox space (normalized 0..1 relative to 640)
            cx = float(output_tensor[0, anchor])
            cy = float(output_tensor[1, anchor])
            w_norm = float(output_tensor[2, anchor])
            h_norm = float(output_tensor[3, anchor])

            # Map to original image coordinates normalized [0..1]
            box_cx_px = cx * 640.0
            box_cy_px = cy * 640.0
            box_w_px = w_norm * 640.0
            box_h_px = h_norm * 640.0

            orig_cx = (box_cx_px - pad_x) / scale
            orig_cy = (box_cy_px - pad_y) / scale
            orig_w_box = box_w_px / scale
            orig_h_box = box_h_px / scale

            norm_x = max(0.0, min(1.0, (orig_cx - orig_w_box / 2.0) / orig_w))
            norm_y = max(0.0, min(1.0, (orig_cy - orig_h_box / 2.0) / orig_h))
            norm_w = max(0.0, min(1.0, orig_w_box / orig_w))
            norm_h = max(0.0, min(1.0, orig_h_box / orig_h))

            # Filter RoadSense: keep only classes 0, 1, 2 (D00, D10, D20)
            # Class 3 (D40) is ignored for observations
            # Class 4 (Repair) is stored separately for potential pothole filtering
            if best_cls in (0, 1, 2):
                thresh = CLASS_THRESHOLDS[cls_name]
                if best_score >= thresh:
                    raw_candidates.append({
                        "anchor": anchor,
                        "classCode": cls_name,
                        "confidence": best_score,
                        "box": {
                            "x": norm_x,
                            "y": norm_y,
                            "width": norm_w,
                            "height": norm_h,
                        },
                        "letterbox_box": {
                            "cx": cx,
                            "cy": cy,
                            "w": w_norm,
                            "h": h_norm,
                        }
                    })
            elif best_cls == 4:
                # Repair box
                if best_score >= CLASS_THRESHOLDS["Repair"]:
                    repair_candidates.append({
                        "anchor": anchor,
                        "classCode": "Repair",
                        "confidence": best_score,
                        "box": {
                            "x": norm_x,
                            "y": norm_y,
                            "width": norm_w,
                            "height": norm_h,
                        }
                    })

        # Apply class-wise NMS on kept crack detections
        crack_dets_nms = class_aware_nms(raw_candidates, iou_thresh=0.45)
        repair_dets_nms = class_aware_nms(repair_candidates, iou_thresh=0.45)

        record = {
            "imageName": img_name,
            "originalWidth": orig_w,
            "originalHeight": orig_h,
            "letterbox": {
                "scale": float(scale),
                "padX": int(pad_x),
                "padY": int(pad_y),
                "newWidth": int(new_w),
                "newHeight": int(new_h),
                "inputSize": 640,
                "padValueNormalized": 114.0 / 255.0,
            },
            "tensorSample": tensor_sample,
            "rawCandidateCount": len(raw_candidates),
            "finalDetections": crack_dets_nms,
            "repairDetections": repair_dets_nms,
        }
        golden_records.append(record)
        print(f"[{img_name}] {orig_w}x{orig_h} -> {len(raw_candidates)} candidates -> {len(crack_dets_nms)} crack detections post-NMS, {len(repair_dets_nms)} repair boxes")
        for d in crack_dets_nms:
            b = d['box']
            print(f"    {d['classCode']}: conf={d['confidence']:.3f}, box=[x={b['x']:.3f}, y={b['y']:.3f}, w={b['width']:.3f}, h={b['height']:.3f}]")

    with open(GOLDEN_JSON, "w", encoding="utf-8") as f:
        json.dump({
            "version": "1.0",
            "modelFile": "road_damage_roadsense.tflite",
            "inputShape": [1, 3, 640, 640],
            "outputShape": [1, 9, 8400],
            "iouThreshold": 0.45,
            "thresholds": CLASS_THRESHOLDS,
            "records": golden_records,
        }, f, indent=2)

    print(f"\nSuccessfully wrote goldens to: {GOLDEN_JSON}")

if __name__ == "__main__":
    main()
