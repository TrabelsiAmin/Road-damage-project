import cv2
from ultralytics import YOLO

print("Loading TariqMap model...")
# Load the TFLite model from the Flutter assets
model = YOLO("app/assets/models/road_damage.tflite")

print("Opening webcam...")
# Open the default PC webcam (index 0)
cap = cv2.VideoCapture(0)

if not cap.isOpened():
    print("Error: Could not open PC webcam.")
    exit()

print("\n--- TariqMap Live Test (PC) ---")
print("Press 'q' on your keyboard to close the window.")

while True:
    ret, frame = cap.read()
    if not ret:
        print("Failed to grab frame.")
        break
        
    # Run YOLO inference on the frame
    results = model(frame, verbose=False)
    
    # Draw bounding boxes on the frame
    annotated_frame = results[0].plot()
    
    # Show it in a desktop window
    cv2.imshow("TariqMap - PC Test Mode", annotated_frame)
    
    # Exit if 'q' is pressed
    if cv2.waitKey(1) & 0xFF == ord('q'):
        break

cap.release()
cv2.destroyAllWindows()
