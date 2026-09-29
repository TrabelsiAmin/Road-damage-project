import os
import random
import cv2
import numpy as np
import ai_edge_litert.interpreter as tflite
import glob

# Config
MODEL_PATH = "app/assets/models/road_damage.tflite"
IMAGE_DIR = "Global_Potholes_Dataset-image"
OUTPUT_DIR = "inference_results"
CLASS_NAMES = ['Crack', 'Pothole', 'Rutting', 'Uneven-Surface']
INPUT_SIZE = 640
CONF_THRESHOLD = 0.25

if not os.path.exists(OUTPUT_DIR):
    os.makedirs(OUTPUT_DIR)

# Load TFLite Model
interpreter = tflite.Interpreter(model_path=MODEL_PATH)
interpreter.allocate_tensors()
input_details = interpreter.get_input_details()
output_details = interpreter.get_output_details()

print(f"Model loaded. Input shape: {input_details[0]['shape']}")

# Find images
image_paths = glob.glob(f"{IMAGE_DIR}/**/*.jpg", recursive=True) + glob.glob(f"{IMAGE_DIR}/**/*.png", recursive=True)
print(f"Found {len(image_paths)} images.")

if len(image_paths) == 0:
    print("No images found to test.")
    exit()

# Shuffle images to test randomly
random.shuffle(image_paths)

found_results = 0
for img_path in image_paths:
    if found_results >= 5:
        break
        
    print(f"Processing {img_path}...")
    
    # Read and preprocess
    img = cv2.imread(img_path)
    if img is None:
        continue
    
    original_h, original_w, _ = img.shape
    
    # Resize to INPUT_SIZE x INPUT_SIZE
    resized = cv2.resize(img, (INPUT_SIZE, INPUT_SIZE))
    
    # Convert BGR to RGB and normalize to [0, 1]
    rgb = cv2.cvtColor(resized, cv2.COLOR_BGR2RGB)
    normalized = rgb.astype(np.float32) / 255.0
    input_data = np.expand_dims(normalized, axis=0)
    
    # Run Inference
    interpreter.set_tensor(input_details[0]['index'], input_data)
    interpreter.invoke()
    output_data = interpreter.get_tensor(output_details[0]['index'])
    
    output = output_data[0] 
    
    num_channels, num_anchors = output.shape
    num_classes = num_channels - 4
    
    boxes = []
    scores = []
    class_ids = []
    
    for anchor in range(num_anchors):
        # Find best class
        class_scores = output[4:4+num_classes, anchor]
        best_class = np.argmax(class_scores)
        best_score = class_scores[best_class]
        
        if best_score > CONF_THRESHOLD:
            # YOLOv8 coordinates are normalized [0..1] in this model export
            cx = output[0, anchor]
            cy = output[1, anchor]
            w = output[2, anchor]
            h = output[3, anchor]
            
            # Convert to Top-Left corner and map to original image size
            x1 = int((cx - w / 2) * original_w)
            y1 = int((cy - h / 2) * original_h)
            w_box = int(w * original_w)
            h_box = int(h * original_h)
            
            boxes.append([x1, y1, w_box, h_box])
            scores.append(float(best_score))
            class_ids.append(best_class)
    
    # Apply NMS
    indices = cv2.dnn.NMSBoxes(boxes, scores, CONF_THRESHOLD, 0.45)
    
    if len(indices) == 0:
        continue # Skip images with no anomalies
        
    print(f"  Found {len(indices)} anomalies.")
    
    # Draw boxes
    for idx in indices:
        box = boxes[idx]
        x1, y1, w_box, h_box = box
        class_id = class_ids[idx]
        score = scores[idx]
        
        label = f"{CLASS_NAMES[class_id]} {score:.2f}"
        print(f"  - {label} at [X:{x1}, Y:{y1}, W:{w_box}, H:{h_box}]")
        
        cv2.rectangle(img, (x1, y1), (x1 + w_box, y1 + h_box), (0, 0, 255), 3)
        cv2.putText(img, label, (x1, y1 - 20), cv2.FONT_HERSHEY_SIMPLEX, 1.2, (0, 0, 255), 3)
    
    # Save output
    out_path = os.path.join(OUTPUT_DIR, f"result_more_{found_results}.jpg")
    cv2.imwrite(out_path, img)
    print(f"  Saved result to {out_path}\n")
    found_results += 1

print("Done.")
