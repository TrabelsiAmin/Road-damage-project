"""Generator script for Phase 2 synthetic demo data SQL.

Creates ~40 clearly marked `is_demo = true` observations around Tunis and Bizerte
with realistic multi-pass clusters, distinct fake device hashes, mixed classes and statuses,
and NO real photos. Includes a clean delete-all-demo SQL statement.
"""
import uuid
import hashlib
import json
import random
from datetime import datetime, timedelta

# Priority Scoring v2 formula
CLASS_WEIGHTS = {'D40': 1.0, 'D20': 0.85, 'D10': 0.5, 'D00': 0.4}
AREA_REF = 0.10
BONUS_SCALE = 2.5
MAX_BONUS = 10.0
HIGH_THRESH = 65.0
LOW_THRESH = 35.0

def calculate_priority_score_v2(dets):
    valid = [d for d in dets if d['confidence'] >= 0.25]
    if not valid:
        return 0.0, 'LOW'
    
    scored = []
    for d in valid:
        w = CLASS_WEIGHTS.get(d['classCode'], 0.4)
        area = max(0.0, min(1.0, d['box']['width'] * d['box']['height']))
        af = min(1.0, (area / AREA_REF) ** 0.5) if area > 0 else 0.0
        s = w * d['confidence'] * af * 100.0
        scored.append((s, w, d, af))
        
    worst_s, worst_w, worst_d, worst_af = max(scored, key=lambda x: x[0])
    base_score = worst_s
    
    bonus = 0.0
    removed = False
    for s, w, d, af in scored:
        if not removed and d is worst_d:
            removed = True
            continue
        bonus += w * d['confidence'] * BONUS_SCALE
    count_bonus = min(MAX_BONUS, bonus)
    raw = min(100.0, base_score + count_bonus)
    
    # Pothole model is weak: cap D40 below HIGH (<= 65) if confidence < 0.50
    if worst_d['classCode'] == 'D40' and worst_d['confidence'] < 0.50:
        raw = min(raw, HIGH_THRESH)
        
    score = round(raw, 2)
    label = 'LOW' if score < LOW_THRESH else ('HIGH' if score > HIGH_THRESH else 'MEDIUM')
    return score, label

# Corridors in Tunis and Bizerte
CORRIDORS = [
    # Tunis: Avenue Habib Bourguiba cluster (3 reports within 12m)
    {"center_lat": 36.8003, "center_lng": 10.1802, "city": "Tunis", "name": "Avenue Bourguiba", "count": 3, "radius_m": 12, "class": "D40", "status": "unconfirmed"},
    # Tunis: Bab Souika cluster (4 reports within 15m)
    {"center_lat": 36.8068, "center_lng": 10.1685, "city": "Tunis", "name": "Bab Souika", "count": 4, "radius_m": 15, "class": "D20", "status": "confirmed"},
    # Tunis: Ariana Center cluster (3 reports within 10m)
    {"center_lat": 36.8625, "center_lng": 10.1955, "city": "Ariana", "name": "Ariana Centre", "count": 3, "radius_m": 10, "class": "D40", "status": "repaired"},
    # Tunis: Ennasr 2 cluster (3 reports within 14m)
    {"center_lat": 36.8732, "center_lng": 10.1588, "city": "Tunis", "name": "Ennasr 2", "count": 3, "radius_m": 14, "class": "D10", "status": "unconfirmed"},
    # Tunis: Le Bardo pair (2 reports within 8m)
    {"center_lat": 36.8092, "center_lng": 10.1415, "city": "Tunis", "name": "Le Bardo", "count": 2, "radius_m": 8, "class": "D20", "status": "confirmed"},
    # Tunis: La Goulette pair (2 reports within 9m)
    {"center_lat": 36.8185, "center_lng": 10.3052, "city": "Tunis", "name": "La Goulette", "count": 2, "radius_m": 9, "class": "D00", "status": "repaired"},
    # Tunis: Lac 2 isolated single reports
    {"center_lat": 36.8378, "center_lng": 10.2395, "city": "Tunis", "name": "Les Berges du Lac", "count": 1, "radius_m": 0, "class": "D40", "status": "unconfirmed"},
    {"center_lat": 36.8450, "center_lng": 10.2600, "city": "Tunis", "name": "Lac 2", "count": 1, "radius_m": 0, "class": "D00", "status": "unconfirmed"},
    {"center_lat": 36.8200, "center_lng": 10.1900, "city": "Tunis", "name": "Montplaisir", "count": 1, "radius_m": 0, "class": "D10", "status": "confirmed"},
    {"center_lat": 36.7900, "center_lng": 10.1700, "city": "Tunis", "name": "Montfleury", "count": 1, "radius_m": 0, "class": "D20", "status": "unconfirmed"},

    # Bizerte: Vieux Port cluster (4 reports within 14m)
    {"center_lat": 37.2762, "center_lng": 9.8738, "city": "Bizerte", "name": "Vieux Port Bizerte", "count": 4, "radius_m": 14, "class": "D40", "status": "confirmed"},
    # Bizerte: Corniche cluster (3 reports within 12m)
    {"center_lat": 37.2885, "center_lng": 9.8650, "city": "Bizerte", "name": "Corniche Bizerte", "count": 3, "radius_m": 12, "class": "D20", "status": "unconfirmed"},
    # Bizerte: Zarzouna Bridge cluster (3 reports within 10m)
    {"center_lat": 37.2655, "center_lng": 9.8790, "city": "Bizerte", "name": "Pont Mobile Zarzouna", "count": 3, "radius_m": 10, "class": "D40", "status": "repaired"},
    # Bizerte: Menzel Jemil pair (2 reports within 11m)
    {"center_lat": 37.2280, "center_lng": 9.9150, "city": "Bizerte", "name": "Menzel Jemil", "count": 2, "radius_m": 11, "class": "D10", "status": "unconfirmed"},
    # Bizerte: Menzel Bourguiba pair (2 reports within 9m)
    {"center_lat": 37.1520, "center_lng": 9.7890, "city": "Bizerte", "name": "Menzel Bourguiba", "count": 2, "radius_m": 9, "class": "D00", "status": "confirmed"},
    # Bizerte: Isolated reports
    {"center_lat": 37.2810, "center_lng": 9.8520, "city": "Bizerte", "name": "Bab Mateur", "count": 1, "radius_m": 0, "class": "D20", "status": "unconfirmed"},
    {"center_lat": 37.2690, "center_lng": 9.8850, "city": "Bizerte", "name": "Port de Pêche", "count": 1, "radius_m": 0, "class": "D40", "status": "unconfirmed"},
    {"center_lat": 37.2950, "center_lng": 9.8600, "city": "Bizerte", "name": "Sidi Salem", "count": 1, "radius_m": 0, "class": "D10", "status": "repaired"},
]

DEVICE_SEEDS = [
    "mobile_sensor_tunis_fleet_01",
    "mobile_sensor_tunis_fleet_02",
    "mobile_sensor_bizerte_bus_07",
    "mobile_sensor_bizerte_patrol_03",
    "citizen_dashcam_contributor_99",
    "municipal_surveyor_van_04",
]
DEVICE_HASHES = [hashlib.sha256(s.encode()).hexdigest() for s in DEVICE_SEEDS]

def generate_sql():
    observations = []
    locations = []
    detections = []
    
    random.seed(20261015)
    base_time = datetime(2026, 10, 10, 8, 30, 0)
    
    total_count = 0
    for cluster_cfg in CORRIDORS:
        c_lat = cluster_cfg["center_lat"]
        c_lng = cluster_cfg["center_lng"]
        cls = cluster_cfg["class"]
        status = cluster_cfg["status"]
        n_pts = cluster_cfg["count"]
        radius_m = cluster_cfg["radius_m"]
        
        for p_idx in range(n_pts):
            total_count += 1
            obs_id = str(uuid.uuid4())
            capture_id = f"demo-cap-{total_count:03d}"
            
            # Offset points within radius in meters
            if radius_m > 0 and n_pts > 1:
                angle = random.uniform(0, 2 * 3.14159)
                r = random.uniform(0, radius_m)
                dlat = (r * random.uniform(0.5, 1.0) / 111000.0) * (1 if random.random() > 0.5 else -1)
                dlng = (r * random.uniform(0.5, 1.0) / (111000.0 * 0.8)) * (1 if random.random() > 0.5 else -1)
            else:
                dlat, dlng = 0.0, 0.0
                
            lat = round(c_lat + dlat, 7)
            lng = round(c_lng + dlng, 7)
            accuracy = round(random.uniform(5.0, 16.0), 1)
            
            # Timestamp spread over past 5 days
            obs_time = base_time + timedelta(
                days=random.uniform(0, 4),
                hours=random.uniform(0, 8),
                minutes=random.uniform(0, 59)
            )
            time_str = obs_time.strftime("%Y-%m-%d %H:%M:%S+00")
            
            # Device hash rotation
            dev_hash = random.choice(DEVICE_HASHES)
            
            # Detections
            conf = round(random.uniform(0.70, 0.95) if cls == 'D40' else random.uniform(0.60, 0.90), 2)
            bw = round(random.uniform(0.28, 0.45), 2)
            bh = round(random.uniform(0.28, 0.45), 2)
            bx = round(random.uniform(0.1, 0.5), 2)
            by = round(random.uniform(0.2, 0.5), 2)
            
            point_dets = [{
                'classCode': cls,
                'confidence': conf,
                'box': {'x': bx, 'y': by, 'width': bw, 'height': bh}
            }]
            
            # Some observations have an auxiliary crack detection
            if random.random() < 0.35 and cls != 'D00':
                aux_cls = 'D00' if cls != 'D10' else 'D20'
                aux_conf = round(random.uniform(0.35, 0.65), 2)
                point_dets.append({
                    'classCode': aux_cls,
                    'confidence': aux_conf,
                    'box': {'x': 0.15, 'y': 0.15, 'width': 0.20, 'height': 0.20}
                })
                
            score, label = calculate_priority_score_v2(point_dets)
            
            observations.append({
                'id': obs_id,
                'capture_id': capture_id,
                'anomaly_type': cls,
                'priority_score': score,
                'priority_label': label,
                'status': status,
                'device_id': dev_hash,
                'created_at': time_str,
                'is_demo': True
            })
            
            locations.append({
                'observation_id': obs_id,
                'latitude': lat,
                'longitude': lng,
                'accuracy_meters': accuracy,
                'captured_at': time_str
            })
            
            for d in point_dets:
                detections.append({
                    'observation_id': obs_id,
                    'class_code': d['classCode'],
                    'confidence': d['confidence'],
                    'box_x': d['box']['x'],
                    'box_y': d['box']['y'],
                    'box_w': d['box']['width'],
                    'box_h': d['box']['height']
                })

    # Build SQL
    sql_lines = [
        "-- =============================================================================",
        "-- Migration: 20261015_demo_data_bizerte_tunis.sql",
        f"-- Synthetic Demonstration Data: ~{len(observations)} observations around Bizerte and Tunis",
        "--",
        "-- Attributes:",
        "--   - Clearly marked is_demo = true on every row",
        "--   - Plausible spatial clusters (< 20m) and single points",
        "--   - Several fake device SHA-256 hashes",
        "--   - Mixed classes (D40, D20, D10, D00) and statuses (unconfirmed, confirmed, repaired)",
        "--   - Accurate Priority Scoring v2 values",
        "--   - NO real photos attached (media_files omitted)",
        "-- =============================================================================",
        "",
        "-- -----------------------------------------------------------------------------",
        "-- 0. CLEANUP SCRIPT: Delete all previous demo records",
        "-- -----------------------------------------------------------------------------",
        "DELETE FROM public.detections WHERE observation_id IN (SELECT id FROM public.observations WHERE is_demo = true);",
        "DELETE FROM public.locations WHERE observation_id IN (SELECT id FROM public.observations WHERE is_demo = true);",
        "DELETE FROM public.media_files WHERE is_demo = true OR observation_id IN (SELECT id FROM public.observations WHERE is_demo = true);",
        "DELETE FROM public.observations WHERE is_demo = true;",
        "",
        "-- -----------------------------------------------------------------------------",
        f"-- 1. Insert Observations ({len(observations)} records)",
        "-- -----------------------------------------------------------------------------",
        "INSERT INTO public.observations (id, capture_id, anomaly_type, priority_score, priority_label, status, device_id, is_demo, created_at) VALUES"
    ]
    
    obs_val_lines = []
    for o in observations:
        obs_val_lines.append(
            f"  ('{o['id']}', '{o['capture_id']}', '{o['anomaly_type']}', {o['priority_score']}, '{o['priority_label']}', '{o['status']}', '{o['device_id']}', true, '{o['created_at']}')"
        )
    sql_lines.append(",\n".join(obs_val_lines) + ";")
    sql_lines.append("")
    
    sql_lines.append(f"-- -----------------------------------------------------------------------------")
    sql_lines.append(f"-- 2. Insert Locations ({len(locations)} records)")
    sql_lines.append(f"-- -----------------------------------------------------------------------------")
    sql_lines.append("INSERT INTO public.locations (observation_id, latitude, longitude, accuracy_meters, captured_at) VALUES")
    loc_val_lines = []
    for l in locations:
        loc_val_lines.append(
            f"  ('{l['observation_id']}', {l['latitude']}, {l['longitude']}, {l['accuracy_meters']}, '{l['captured_at']}')"
        )
    sql_lines.append(",\n".join(loc_val_lines) + ";")
    sql_lines.append("")
    
    sql_lines.append(f"-- -----------------------------------------------------------------------------")
    sql_lines.append(f"-- 3. Insert Detections ({len(detections)} records)")
    sql_lines.append(f"-- -----------------------------------------------------------------------------")
    sql_lines.append("INSERT INTO public.detections (observation_id, class_code, confidence, box_x, box_y, box_w, box_h) VALUES")
    det_val_lines = []
    for d in detections:
        det_val_lines.append(
            f"  ('{d['observation_id']}', '{d['class_code']}', {d['confidence']}, {d['box_x']}, {d['box_y']}, {d['box_w']}, {d['box_h']})"
        )
    sql_lines.append(",\n".join(det_val_lines) + ";")
    sql_lines.append("")
    
    sql_lines.append("-- =============================================================================")
    sql_lines.append("-- STANDALONE DELETE SCRIPT (Can be run independently to purge demo data)")
    sql_lines.append("-- =============================================================================")
    sql_lines.append("-- DELETE FROM public.detections WHERE observation_id IN (SELECT id FROM public.observations WHERE is_demo = true);")
    sql_lines.append("-- DELETE FROM public.locations WHERE observation_id IN (SELECT id FROM public.observations WHERE is_demo = true);")
    sql_lines.append("-- DELETE FROM public.observations WHERE is_demo = true;")
    sql_lines.append("")
    
    return "\n".join(sql_lines)

if __name__ == '__main__':
    sql = generate_sql()
    out_path = 'supabase/migrations/20261015_demo_data_bizerte_tunis.sql'
    with open(out_path, 'w', encoding='utf-8') as f:
        f.write(sql)
    print(f"Generated demo SQL file at {out_path} ({len(sql.splitlines())} lines).")
