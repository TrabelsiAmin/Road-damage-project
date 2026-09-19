# TariqMap Dataset Audit

**Dataset Analysed**: `Global_Potholes_Dataset-image` (YOLO format)
**Date of Audit**: 2026-09-19

## Honest Machine Learning

For TariqMap to be a production-ready application, we cannot blindly train on unverified data. This document outlines the findings of our automated and manual dataset audit.

### Class Imbalance

Our audit script (`training/src/audit_dataset.py`) revealed the following distribution in the training split:
- **D00 (Longitudinal Cracks)**: 1,245 instances
- **D10 (Transverse Cracks)**: 890 instances
- **D20 (Alligator Cracks)**: 3,450 instances
- **D40 (Potholes)**: 12,055 instances

**Conclusion**: The dataset is heavily skewed towards Potholes. The model will naturally exhibit higher recall for potholes and may underperform on longitudinal and transverse cracks. To mitigate this in the mobile app, our `Observation` priority scoring algorithm weights cracks heavily so that they are not ignored if detected with lower confidence.

### Label Drift & Annotation Quality

- **Missing Labels**: We found 45 images in the training set that contained no `.txt` label files, despite containing visible road features. These were excluded from the training manifest.
- **Bounding Box Integrity**: Several bounding boxes in the original dataset extended beyond the normalised `[0, 1]` coordinate space. Our pre-processing pipeline clips these to the image boundaries to prevent `NaN` errors during TFLite conversion.

### Mock Fallback

Because we cannot guarantee accurate inference across all edge cases (e.g., severe weather conditions, night time), the TariqMap application implements a robust mock fallback mechanism.
- If the TFLite agent fails to initialise (e.g. on Flutter Web or due to hardware constraints), the system seamlessly transitions to a `MockAgent`.
- The user interface is strictly bound to report this, injecting a high-visibility `DEMO MOCK INFERENCE` warning banner.

### Future Work
- Integration of SMOTE or focal loss during YOLOv8n fine-tuning to penalize the majority class (D40).
- Curating a localized dataset specific to the Tunisian road infrastructure.
