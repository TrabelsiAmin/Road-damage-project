# Ministry Road-Maintenance Command Center (TariqMap)

The TariqMap Authority Dashboard has been upgraded into a comprehensive **Ministry Road-Maintenance Command Center** designed for the Tunisian Ministry of Equipment and Housing (Ministère de l'Équipement et de l'Habitat — DGPC), municipal road services, and highway operators (Société Tunisie Autoroutes).

---

## 1. Core Architecture & Views

The Command Center is structured into 8 integrated operational views:

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    TariqMap Command Center Top Navigation                       │
├──────────────┬──────────────────┬──────────┬──────────────┬──────────┬──────────┤
│ 1. Overview  │ 2. Action Center │ 3. Carte │ 4. Tronçons  │ 5. Trend │ 6. IA    │
│  (10 KPIs)   │  (Work Queues)   │   SIG    │  (Risque)    │ (Analyse)│ (Qualité)│
├──────────────┴──────────────────┴──────────┴──────────────┴──────────┴──────────┤
│                 Global Multi-Dimensional Filter Bar                             │
│   [Today|7d|30d|90d|All] [Gouvernorat] [Commune] [Classe] [Priorité] [Statut]   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

1. **Executive Overview (`overview`)**:
   - 10 real-data KPI cards with delta indicators comparing against prior periods.
   - Embeds the macro road health index (RHI) and technical recommendation assistant (RAG).
2. **Operations Action Center (`action_center`)**:
   - 8 operational work queues:
     - `Critiques`: High-priority defects and severe potholes (D40) needing immediate patching.
     - `En attente validation`: New mobile/video reports requiring authority confirmation.
     - `En retard (>14j)`: Confirmed anomalies exceeding the standard 14-day SLA.
     - `Non assignées`: Anomalies without contractor or municipal brigade assignment.
     - `En cours`: Worksites currently undergoing active road repairs.
     - `À vérifier`: Repaired sections awaiting supervisory inspection.
     - `Répétés (>1)`: Multiple concordant reports on the same 20m cluster or corridor.
     - `GPS faible (>25m)`: Reports with poor GNSS accuracy flagged for field survey.
   - Comprehensive operational table with individual actions and safe bulk operations (status, priority, assignment, CSV export).
3. **GIS Operations Map (`gis_map`)**:
   - 20m DBSCAN spatial clusters, dynamic color-coding by priority, size by report density.
   - Interactive layer controls: Active anomalies, Critical locations, 20m Clusters, National Road Corridors, and Repaired locations.
   - Popups linking directly to the technical RAG recommendation engine.
4. **Road Segment Risk Matrix (`road_segments`)**:
   - Deterministic corridor aggregation for major Tunisian routes (A1, A4, RN1, RN8, RN9, RR21, etc.).
   - Transparent composite risk scoring (0–100) with human-readable explanations.
   - Estimated repair budget based on official DGPC unit pricing schedules.
5. **Analytics & Trends (`analytics`)**:
   - Backlog evolution time series (New reports vs. Repaired worksites).
   - Regional backlog rankings by Tunisian Governorate.
   - Mean resolution time (days) and repair completion percentages.
6. **Data Quality & AI Telemetry (`data_quality`)**:
   - TFLite model inference confidence distribution (High >80%, Medium 50–80%, Low <50%).
   - Class distribution breakdown across D00, D10, D20, D40.
   - GNSS accuracy telemetry and media attachment verification.
   - Authority feedback channel for false positives and retraining.
7. **Official Reports & Exports (`reports`)**:
   - Standard CSV with UTF-8 BOM for Microsoft Excel.
   - Native Excel TSV export.
   - Standard GeoJSON `FeatureCollection` for QGIS / ArcGIS.
   - Printable Work Order summary sheet (Fiche de tournée d'intervention).
8. **Audit Trail & Governance (`audit`)**:
   - Chronological log of all validations, status transitions, brigade assignments, and verifications.

---

## 2. KPI Definitions & Calculations

| KPI Name | Formula / Criteria | Unit / Target |
| :--- | :--- | :--- |
| **Active Anomalies** | Count where `status IN ('unconfirmed', 'confirmed', 'in_progress')` | Integer |
| **Critical Anomalies** | Count where `priority_label = 'HIGH' OR anomaly_type = 'D40'` | Integer |
| **High-Risk Segments** | Corridors with composite `riskScore >= 60` | Integer |
| **New Reports** | Reports captured within active date filter window | Integer (with delta vs prior) |
| **Unconfirmed Reports** | Reports with `status = 'unconfirmed'` | Integer |
| **Overdue Cases** | Confirmed reports older than 14 days without completion | Integer (SLA breach) |
| **Repairs In Progress** | Cases with `status = 'in_progress'` | Active sites |
| **Repairs Completed** | Cases with `status = 'repaired'` | Target > 75% |
| **Average Response Time** | Mean days from detection to status `repaired` | Target < 7 days |
| **Estimated Repair Budget** | Sum of estimated repair unit costs (D40: 180 DT, D20: 450 DT, D00/D10: 100 DT) | Dinars Tunisiens (TND) |

---

## 3. Road Segment Risk Formulation

The risk score of any corridor or municipal segment is computed deterministically:

$$\text{RiskScore} = \min(100, (\text{SeverityScore} \times 0.45 + \text{AgeScore} \times 0.25 + \text{DensityScore} \times 0.20 + \text{GPSFactor} \times 0.10) \times \text{ImportanceWeight})$$

Where:
- $\text{SeverityScore}$: Weighted by defect severity (D40 pothole = 100, D20 alligator crack = 75, D10 = 50, D00 = 40).
- $\text{AgeScore}$: Backlog age capped at 45 days: $\min(100, \frac{\text{AgeDays}}{45} \times 100)$.
- $\text{DensityScore}$: Logarithmic report recurrence density.
- $\text{ImportanceWeight}$: Strategic multiplier (Autoroutes = 1.30, Routes Nationales = 1.15, Routes Régionales = 1.05, Voirie Urbaine = 1.00).

---

## 4. Security & Access Control

- **Role Separation**: Citizens and anonymous visitors can browse public blurred thumbnails and macro statistics. Original high-resolution photos and workflow management actions (Validate, Reject, Assign, Repair) strictly require authority authentication (`is_authority = true`).
- **Temporary Signed URLs**: Authority users view high-resolution evidence through 10-minute signed URLs generated server-side by Supabase Storage, auto-refreshing 30 seconds before expiration.
- **Audit Immutability**: All status transitions, case assignments, and bulk actions are committed to `maintenance_events` with authenticated user timestamps.
