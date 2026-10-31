# Meeting Minutes (PV)
Team : 6B (TariqMap Project)  
Subject: Discussion on Agentic System Modeling, Contextual RAG Integration, and Map Location Accuracy

1. Modelisation of the Agentic System
The discussion focused on replacing a single detection pipeline with a collaborative multi-agent architecture across edge and central tiers:
- Perception Agent (Edge): Runs on-device YOLO models (TFLite) to detect cracks and potholes, while filtering out false positives using road repair patch detection.
- Telemetry & Priority Agents: Validate sensor metadata, enforce GPS quality thresholds, and compute an objective triage priority score for each detected hazard.
- Territorial & Decision Agents: Group repeated observations, identify municipal jurisdiction, and prepare formal intervention work orders.
- Failure Isolation ("Honest ML"): Agents operate independently. If a model or delegate fails, an explicit error is recorded without interrupting data collection or returning fake data.

2. Contextual RAG Integration
The team agreed that the RAG component must act as an engineering decision-support tool rather than an isolated conversational chatbot:
- Technical Knowledge Base: Indexes official pavement degradation manuals and RDD2022 standards using dense vector embeddings (BGE-M3) and FAISS.
- Actionable Recommendations: Enriches visual detections with technical diagnostics (root causes like fatigue or moisture) and standard repair protocols (milling, sealing, patching).
- Privacy and Security: Coordinates, device IDs, and images are strictly filtered out before sending queries to the LLM (Qwen2.5-7B), querying only defect classes and priority levels.
- Grounded Answers: Outputs must cite exact documentation passages to eliminate hallucinations.

3. Map Location Accuracy Enhancement
The discussion addressed overcoming smartphone GPS drift (5–15m errors) and the flaws of coordinate rounding, which splits identical defects into multiple pins:
- Quality Gating: Automatically discards or flags observations with GPS accuracy worse than 25 meters.
- Sensor Fusion: Uses mobile IMU sensors (accelerometer/gyroscope) with Kalman filtering to smooth vehicle inspection trajectories.
- Metric Spatial Clustering (DBSCAN): Replaces coordinate grids with PostGIS distance clustering (20m radius) to merge repeated passes into a single physical hazard.
- Map Matching & Weighted Centroids: Snaps coordinates to official road network centerlines and weights cluster center positions by individual GPS accuracy.

4. Points Requiring Further Work
- Optimize on-device TFLite inference in background isolates for continuous camera capture.
- Connect the FastAPI RAG service to the authority dashboard technical recommendation panel.
- Implement the mobile Kalman filter for trajectory stabilization during vehicle runs.
- Deploy the PostGIS road-snapping API to link clusters to official road segments.
