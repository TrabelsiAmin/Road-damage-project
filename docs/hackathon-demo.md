# TariqMap Hackathon Demo Script

This document provides a step-by-step guide on how to present TariqMap to the judges during the hackathon. It focuses on the core value propositions: **Offline-First Resilience**, **Honest ML**, and **Data Completeness**.

## 1. The Offline-First Scenario
*Goal: Prove the app works without internet.*

1. **Setup**: Turn off WiFi and Cellular Data on the demo device.
2. **Action**: Open TariqMap. Tap "Live Camera".
3. **Demo**: Point the camera at a printed photograph of a pothole (or a monitor).
4. **Highlight**: 
   - The bounding boxes appear in real-time.
   - The FPS and Inference Latency diagnostics in the top-right corner.
   - Point out that inference is happening 100% locally on the TFLite model.
5. **Capture**: Press the capture button. Show the generated `ResultScreen`.
6. **Result Screen**: Emphasize the "Priority Score". Explain that this isn't just confidence; it's a weighted score based on the severity of the damage class.

## 2. The Honest ML Principle
*Goal: Show that we don't fake inference when things break.*

1. **Setup**: Ensure the app is running in the iOS Simulator or Flutter Web (where the native TFLite delegate might fail or is purposefully disabled for the demo).
2. **Action**: Load an image.
3. **Highlight**: Point out the highly visible red `DEMO MOCK INFERENCE` banner.
4. **Talking Point**: "We believe in honest AI. If the hardware accelerator fails, we don't silently return fake data. We explicitly flag the payload as mocked, ensuring data integrity in the central database."

## 3. The Synchronization Engine
*Goal: Demonstrate background data recovery.*

1. **Setup**: While still offline, navigate back to the `HomeScreen`.
2. **Highlight**: Point out the orange cloud icon indicating "Pending Sync".
3. **Action**: Turn WiFi/Data back on.
4. **Action**: Tap the pending sync icon, or pull-to-refresh on the Home Screen.
5. **Highlight**: Show the observations transitioning from `Pending` -> `Uploading` -> `Synced` (green checkmark).
6. **Backend Check**: (Optional) Open the FastAPI backend logs on your laptop to show the incoming POST requests containing the full JSON payload, complete with GPS coordinates and priority scores.

## 4. Closing Argument
TariqMap is an offline-first capture and multi-agent detection slice: audited data strategy, three disjoint agents (WP3 pavement first), honest mock banners when weights are missing, SQLite persistence, and a retryable sync queue. SIG matching, incident dashboards, and RAG are specified, not shipped as production. No mAP is claimed until `src.evaluate` reports `status: OK`.
