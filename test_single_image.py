import os
import cv2
import numpy as np
import ai_edge_litert.interpreter as tflite

# Config
MODEL_PATH = "app/assets/models/road_damage.tflite"
IMAGE_PATH = r"C:\manus\TariqMap\Global_Potholes_Dataset-image\images\0a90c98c-345f-4a1a-a5a7-26010f1d356f.jpg"
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

print(f"Processing {IMAGE_PATH}...")

# Read and preprocess
img = cv2.imread(IMAGE_PATH)
if img is None:
    print("Failed to read image.")
    exit()

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
    class_scores = output[4:4+num_classes, anchor]
    best_class = np.argmax(class_scores)
    best_score = class_scores[best_class]
    
    if best_score > CONF_THRESHOLD:
        cx = output[0, anchor]
        cy = output[1, anchor]
        w = output[2, anchor]
        h = output[3, anchor]
        
        x1 = int((cx - w / 2) * original_w)
        y1 = int((cy - h / 2) * original_h)
        w_box = int(w * original_w)
        h_box = int(h * original_h)
        
        boxes.append([x1, y1, w_box, h_box])
        scores.append(float(best_score))
        class_ids.append(best_class)

# Apply NMS
indices = cv2.dnn.NMSBoxes(boxes, scores, CONF_THRESHOLD, 0.45)

print(f"Found {len(indices)} anomalies.")

for idx in indices:
    box = boxes[idx]
    x1, y1, w_box, h_box = box
    class_id = class_ids[idx]
    score = scores[idx]
    
    label = f"{CLASS_NAMES[class_id]} {score:.2f}"
    print(f"- {label} at [X:{x1}, Y:{y1}, W:{w_box}, H:{h_box}]")
    
    cv2.rectangle(img, (x1, y1), (x1 + w_box, y1 + h_box), (0, 0, 255), 3)
    cv2.putText(img, label, (x1, y1 - 20), cv2.FONT_HERSHEY_SIMPLEX, 1.2, (0, 0, 255), 3)

out_path = os.path.join(OUTPUT_DIR, "result_specific.jpg")
cv2.imwrite(out_path, img)
print(f"Saved result to {out_path}")
