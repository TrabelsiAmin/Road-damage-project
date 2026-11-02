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


---

## 5. UTF-8 Encoding & Internationalization Standards

- **Encoding Standard**: All dashboard source files (`.jsx`, `.js`, `.css`, `.json`, `.html`, `.md`) are strictly saved in standard UTF-8 without Byte Order Mark (BOM).
- **French Diacritics Integrity**: Corrupted Windows-1252 / Latin-1 double-encoded byte sequences (such as `MÃ©triques`, `PrioritÃ©`, `â€”`, `â€¢`, `LÃ‰GENDE`) are strictly prohibited and prevented.
- **Automated Verification**: The test suite includes `dashboard/src/utils/encodingValidation.test.js` which validates source integrity and ensures proper accents (`é`, `è`, `à`, `ç`, `ê`, `ô`, `É`) and symbols (`•`, `–`, `—`, `«`, `»`) are present.
- **Bilingual Switching**: The dashboard provides real-time switching between French (`fr`, default) and English (`en`) across all views, tooltips, dialogs, map controls, and export generators without page reload.

---

## 6. Leaflet Map Lifecycle & GIS Architecture

The interactive map is powered by Leaflet 1.9.4 with standard OpenStreetMap cartography. It is engineered for resilience in React 18 Strict Mode and dynamic multi-tab layouts:

### 6.1 Lifecycle Safety (React 18 StrictMode)
- **Separation of Concerns**: Map container creation is strictly isolated from marker updates and camera controls:
  1. `5a. Leaflet Map Instance Lifecycle`: Runs once on container mount (`[]`). Cleans any stale `_leaflet_id` before instantiating `L.map`, binds OSM tile layer, sets up `ResizeObserver`, and returns a cleanup function that tears down `map.remove()`, disconnects observer, and resets layer references.
  2. `5b. Size Invalidation on Visibility`: Watches `[activeNavTab, isSidebarCollapsed]`. Fires `requestAnimationFrame(() => map.invalidateSize())` whenever the overview or GIS map becomes visible.
  3. `5c. Markers & Bounds Calculation`: Watches `[mapReady, validClusters, mapLayers.roadSegments]`. Clears and repopulates the markers layer group without recreating the underlying Leaflet instance.
  4. `5d. Focus Marker & Camera Navigation`: Smoothly flies the viewport (`map.flyTo`) to selected defects without resetting existing layers.

### 6.2 Coordinate Validation & Sanitization
- Before any point is added to `L.marker` or `L.latLngBounds`, it passes through `isValidLatLng(lat, lng)` in `src/utils/mapValidation.js`:
  - Enforces finite numbers.
  - Validates geographical bounds: Latitude $\in [-90, 90]$, Longitude $\in [-180, 180]$.
  - Excludes uninitialized origin points (Null Island: `0, 0`).
  - Empty cluster collections do not trigger `fitBounds([])`, preventing Leaflet runtime crashes.

### 6.3 CSS Dimensions & Responsive Layout
- Explicit container dimensions prevent 0x0 collapsed views:
  - `.main-layout`: `min-height: 560px` (desktop grid `1fr 520px`).
  - `.map-wrapper`: `min-height: 560px`.
  - `.map-wrapper > div, .leaflet-container`: `width: 100%; height: 100%; min-height: inherit;`.
  - Responsive breakpoint (`@media (max-width: 1100px)`): Switches layout to single column with `.map-wrapper { height: 420px; min-height: 420px; }`.
  - Hidden state: Uses `.main-layout.hidden-map { display: none !important; }` to maintain the Leaflet DOM node during tab navigation without interfering with CSS grid layouts.

### 6.4 Non-Blocking Map Overlays
- **Loading State**: Displays a compact spinner banner (`Chargement de la carte…`) while initial data is fetched.
- **Tile Error Banner**: Listens to Leaflet tile layer `tileerror` events and displays a non-blocking network warning banner without covering the map.
- **Empty State**: Informs the user when no geolocated anomalies match active filters (`Aucune anomalie géolocalisée dans les filtres sélectionnés.`).
- **Data Error State**: Displays error notification with an inline `Réessayer` button to reload Supabase data.

---

## 7. Development, Testing & Verification Commands

```bash
# Navigate to dashboard directory
cd dashboard

# Install dependencies cleanly
npm ci --no-audit --no-fund

# Run complete Vitest unit test suite (60 tests across 11 test files)
npm test -- --run

# Run Vite production build
npm run build

# Start local Vite development server
npm run dev
```


---

## 8. Dark Mode Theme System

The Command Center includes a full **Dark Mode / Light Mode** theme toggle system:

- **Theme Toggle Control**: Located in the topbar adjacent to the language selector, displaying dynamic `Sun` / `Moon` icons and localized labels (`Clair` / `Sombre` in FR, `Light` / `Dark` in EN).
- **Zero-Flash Pre-Mount Initialization**: An inline script in `dashboard/index.html` inspects `localStorage` (`tariqmap_theme`) and falls back to system preferences (`prefers-color-scheme: dark`) before React mounts, preventing any white flashes on reload.
- **Dual CSS Root Selectors**: Applies to both `[data-theme="dark"]` and `document.body.dark-mode`.
- **Theme Variables**:
  - Dark Primary Background: `#090e17`
  - Dark Secondary Surfaces: `#0f172a`
  - Dark Card Background: `#141f32`
  - Dark Borders: `#1e2e47`
  - Dark Text: `#f8fafc` (main), `#94a3b8` (muted), `#64748b` (dim)
- **Leaflet Cartography in Dark Mode**: OpenStreetMap tiles are styled with an inverted contrast filter (`filter: invert(100%) hue-rotate(180deg) brightness(95%) contrast(90%);`) applied directly to `.leaflet-tile-pane`. Marker pins, DBSCAN clusters, popups, and layer overlays remain unaffected, retaining full color accuracy and high contrast.

---

## 9. 21st.dev-Inspired UI Redesign & Shell Architecture

The dashboard outer layout has been reimagined with **21st.dev-inspired modern dashboard primitives**, combining high-density ministry operational utilities with clean visual hierarchy:

### 9.1 Collapsible Sidebar Navigation (`Sidebar.jsx`)
- **Desktop Expanded Width (260px)**: Displays full ministry branding (`TariqMap - DGPC · Ministère`), primary navigation links with active indicators and live notification badges (`Critiques`, `Clusters`), and an integrated user status card with logout action.
- **Desktop Collapsed Width (68px)**: Compact icon-only rail mode for maximized GIS map viewing. Tooltips display full link names and badges on hover.
- **Mobile Drawer (< 1024px)**: Slide-out off-canvas drawer triggered by the topbar hamburger button, accompanied by a darkened backdrop (`.tm-sidebar-backdrop`) for focus. Automatically dismisses upon link selection.
- **Dedicated Sidebar Footer**: Contains bilingual language switcher (`FR` / `EN`), light/dark theme toggle (`Sun` / `Moon`), and quick authority login / user session management.

### 9.2 Operations Topbar & Live Search (`Topbar.jsx`)
- **Breadcrumbs Navigation**: Clean trail indicating the active operational context (`TariqMap > Current View`).
- **Live Search Field**: Real-time filtering across observations, defect classification codes (`D00`, `D10`, `D20`, `D40`), road segments, municipal borders, and governorates.
- **System Status Indicators**: Includes demo data warning pill (`DONNÉES DE DÉMO`), last-updated timestamp (`HH:mm:ss`), asynchronous refresh button with spin animation, AI validation metrics modal launcher, and quick CSV export.
- **Persistent Authority Chip**: Compact badge signaling whether the active session holds verified road authority credentials (`AUTORITÉ VOIRIE`) or standard view-only permissions.

### 9.3 21st.dev Bento Stat Cards (`StatCard.jsx`)
- **Bento Grid Presentation**: Cards feature subtle elevation, theme-aware surface borders, colored icon circles, high-contrast KPI metrics, and delta indicator pills (`+`, `-`, neutral) comparing against prior periods.
- **Direct Queue Routing**: Clicking actionable stat cards directly navigates the operator to the corresponding queue in the Operations Action Center.

### 9.4 Reusable UI Components
- **`StatusBadge.jsx`**: High-contrast status badges for `unconfirmed`, `confirmed`, `in_progress`, `repaired`, and `rejected` states with dedicated SVG icons and localized descriptions.
- **`PriorityBadge.jsx`**: Priority indicators for `CRITICAL`, `HIGH`, `MEDIUM`, and `LOW` with severity icons and optional calculated priority scores.
- **`EmptyState.jsx`**: Structured empty state card with icon, title, description, and action button for zero-result states.
- **`PageHeader.jsx`**: Standardized header block with title, breadcrumb trail, and contextual action buttons.

### 9.5 Test Coverage & Verification
- Unit test suite (`components.test.jsx`) validates rendering and localization across all new UI components under both French and English settings.
- All 72 unit tests across 13 test files pass cleanly (`npm test -- --run`). Production builds complete cleanly in ~3 seconds (`npm run build`).
