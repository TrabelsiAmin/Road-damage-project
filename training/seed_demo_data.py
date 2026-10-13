"""
TariqMap Demo Data Seed & Cleanup Utility.

Generates realistic road damage observations around Tunisian cities
(Tunis, Bizerte, Sousse) for dashboard testing and demo presentations.
All records are explicitly flagged with `is_demo = True`.

Usage:
    python training/seed_demo_data.py --count 30 --city tunis
    python training/seed_demo_data.py --clean
"""
import argparse
import json
import os
import random
import ssl
import sys
import urllib.request
import urllib.error
import uuid
from datetime import datetime, timedelta, timezone

DEFAULT_SUPABASE_URL = "https://lendqcjihusqkmxansbl.supabase.co"
DEFAULT_ANON_KEY = (
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
    "eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxlbmRxY2ppaHVzcWtteGFuc2JsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAyODA3ODYsImV4cCI6MjEwNTg1Njc4Nn0."
    "F1FS2HZNf7qEbTx14WBSAOHeCWTGsA5OMZghgw_YNNs"
)

CITY_CENTERS = {
    "tunis": {"lat": 36.8065, "lng": 10.1815, "name": "Tunis Centre / Habib Bourguiba"},
    "bizerte": {"lat": 37.2744, "lng": 9.8739, "name": "Bizerte Port & Corniche"},
    "sousse": {"lat": 35.8256, "lng": 10.6084, "name": "Sousse Ville & Medina"},
}

SEVERITY_WEIGHTS = {
    "D40": 1.00,  # Pothole
    "D20": 0.90,  # Alligator crack
    "D00": 0.70,  # Longitudinal crack
    "D10": 0.70,  # Transverse crack
}

SAMPLE_DEMO_IMAGES = {
    "D40": "https://images.unsplash.com/photo-1515162816999-a0c47dc192f7?w=800&auto=format&fit=crop&q=80",
    "D20": "https://images.unsplash.com/photo-1544620347-c4fd4a3d5957?w=800&auto=format&fit=crop&q=80",
    "D00": "https://images.unsplash.com/photo-1590674899484-d5640e854abe?w=800&auto=format&fit=crop&q=80",
    "D10": "https://images.unsplash.com/photo-1590674899484-d5640e854abe?w=800&auto=format&fit=crop&q=80",
}

ORGANIZATIONS = {
    "Municipality": "11111111-1111-4111-8111-111111111111",
    "Ministry of Equipment": "22222222-2222-4222-8222-222222222222",
    "Tunisia Autoroutes": "33333333-3333-4333-8333-333333333333",
}

def get_client(service_key_override=None):
    url = os.environ.get("TARIQMAP_SUPABASE_URL", DEFAULT_SUPABASE_URL).rstrip("/")
    key = service_key_override or os.environ.get("TARIQMAP_SUPABASE_SERVICE_ROLE_KEY") or DEFAULT_ANON_KEY
    ctx = ssl._create_unverified_context()
    return url, key, ctx

def request_rest(method, endpoint, payload=None, params=None, service_key_override=None):
    url, key, ctx = get_client(service_key_override)
    full_url = f"{url}/rest/v1/{endpoint}"
    if params:
        query_string = "&".join(f"{k}={v}" for k, v in params.items())
        full_url += f"?{query_string}"

    headers = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
        "Accept": "application/json",
        "Prefer": "return=representation",
    }

    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    req = urllib.request.Request(full_url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, context=ctx) as response:
            res_body = response.read().decode("utf-8")
            return json.loads(res_body) if res_body else []
    except urllib.error.HTTPError as e:
        err_msg = e.read().decode("utf-8")
        raise RuntimeError(f"HTTP {e.code} on {method} {endpoint}: {err_msg}")

def seed_demo_data(count=25, city="tunis"):
    print(f"\n[Seed] Generating {count} DEMO road damage observations in {city.upper()}...")
    center = CITY_CENTERS.get(city.lower(), CITY_CENTERS["tunis"])
    base_lat = center["lat"]
    base_lng = center["lng"]

    classes = ["D40", "D20", "D00", "D10"]
    actors = list(ORGANIZATIONS.keys())
    statuses = ["unconfirmed", "unconfirmed", "confirmed", "scheduled", "repaired"]

    seeded_obs = []
    seeded_locs = []
    seeded_dets = []
    seeded_media = []

    # Generate distinct synthetic devices to test crowd-confirmation
    device_pool = [f"demo-device-{i:03d}" for i in range(1, 6)]

    # Clustered hotspots to demonstrate 20m distance grouping
    hotspots = [
        (base_lat + random.uniform(-0.015, 0.015), base_lng + random.uniform(-0.015, 0.015))
        for _ in range(max(3, count // 6))
    ]

    now = datetime.now(timezone.utc)

    for i in range(count):
        obs_id = str(uuid.uuid4())
        capture_id = str(uuid.uuid4())
        cls = random.choice(classes)
        actor = random.choice(actors)
        org_id = ORGANIZATIONS[actor]
        status = random.choice(statuses)

        # 60% chance to pick a hotspot with small jitter (< 15 meters)
        if random.random() < 0.6 and hotspots:
            hs_lat, hs_lng = random.choice(hotspots)
            lat = hs_lat + random.gauss(0, 0.0001)  # ~11m
            lng = hs_lng + random.gauss(0, 0.0001)
        else:
            lat = base_lat + random.uniform(-0.02, 0.02)
            lng = base_lng + random.uniform(-0.02, 0.02)

        conf = round(random.uniform(0.55, 0.94), 2)
        score = round((SEVERITY_WEIGHTS[cls] * conf) * 100, 1)

        if score >= 70:
            priority_label = "CRITICAL"
        elif score >= 40:
            priority_label = "HIGH"
        elif score >= 20:
            priority_label = "MEDIUM"
        else:
            priority_label = "LOW"

        age_days = random.randint(0, 14)
        created_at = (now - timedelta(days=age_days, hours=random.randint(1, 23))).isoformat()
        device_id = random.choice(device_pool)

        seeded_obs.append({
            "id": obs_id,
            "capture_id": capture_id,
            "created_by": None,
            "organization_id": org_id,
            "device_id": device_id,
            "source": "camera",
            "captured_at": created_at,
            "priority_score": score,
            "priority_label": priority_label,
            "anomaly_type": cls,
            "model_bundle_version": "2026.09.23-rdd2022",
            "created_at": created_at,
            "is_demo": True,
            "status": status,
        })

        seeded_locs.append({
            "observation_id": obs_id,
            "latitude": round(lat, 6),
            "longitude": round(lng, 6),
            "accuracy_meters": round(random.uniform(3.5, 9.8), 1),
            "captured_at": created_at,
        })

        # Add primary detection box
        bw = round(random.uniform(0.12, 0.45), 3)
        bh = round(random.uniform(0.08, 0.35), 3)
        bx = round(random.uniform(0.1, 1.0 - bw - 0.05), 3)
        by = round(random.uniform(0.2, 1.0 - bh - 0.05), 3)

        seeded_dets.append({
            "id": str(uuid.uuid4()),
            "observation_id": obs_id,
            "agent_run_id": None,
            "class_code": cls,
            "confidence": conf,
            "box_x": bx,
            "box_y": by,
            "box_w": bw,
            "box_h": bh,
            "is_mock": False,
            "model_bundle_version": "2026.09.23-rdd2022",
            "detected_at": created_at,
        })

        # Attach sample media file
        seeded_media.append({
            "id": str(uuid.uuid4()),
            "observation_id": obs_id,
            "bucket": "observation-images",
            "storage_path": f"demo/{cls.lower()}_{i}.jpg",
            "public_url": SAMPLE_DEMO_IMAGES[cls],
            "media_type": "image",
            "mime_type": "image/jpeg",
            "file_size_bytes": random.randint(180000, 450000),
            "uploaded_at": created_at,
            "created_at": created_at,
        })

    # Batch insert into Supabase
    print(f" -> Inserting {len(seeded_obs)} observations...")
    request_rest("POST", "observations", payload=seeded_obs)

    print(f" -> Inserting {len(seeded_locs)} locations...")
    request_rest("POST", "locations", payload=seeded_locs)

    print(f" -> Inserting {len(seeded_dets)} detections...")
    request_rest("POST", "detections", payload=seeded_dets)

    print(f" -> Inserting {len(seeded_media)} media records...")
    request_rest("POST", "media_files", payload=seeded_media)

    print(f"[Success] Seeded {count} DEMO records in {city.upper()}!")
    print(f"  City: {center['name']} ({base_lat}, {base_lng})")
    print(f"  All records marked with is_demo = True")
    print(f"  Run 'python training/seed_demo_data.py --clean' to purge them anytime.")

def cleanup_demo_data():
    print("\n[Clean] Querying and purging DEMO observations...")
    try:
        # Find demo observations
        rows = request_rest("GET", "observations", params={"is_demo": "eq.true", "select": "id"})
        if not rows:
            print("No demo records found.")
            return

        demo_ids = [r["id"] for r in rows]
        print(f"Found {len(demo_ids)} demo records to clean up.")

        # If running with service key, we can delete directly
        url, key, ctx = get_client()
        is_service = "service_role" in key or "TARIQMAP_SUPABASE_SERVICE_ROLE_KEY" in os.environ

        if is_service:
            request_rest("DELETE", "observations", params={"is_demo": "eq.true"})
            print(f"[Success] Deleted {len(demo_ids)} demo observations and cascading child rows.")
        else:
            # Fallback when running with anon key without delete permission:
            # Mark them as dismissed or clean through REST if anon delete is permitted
            try:
                request_rest("DELETE", "observations", params={"is_demo": "eq.true"})
                print(f"[Success] Deleted {len(demo_ids)} demo records.")
            except Exception as e:
                print(f"[Notice] Anon key cannot hard-delete rows ({e}).")
                print("Setting status = 'dismissed' for demo records as soft cleanup.")
                request_rest("PATCH", "observations", payload={"status": "dismissed"}, params={"is_demo": "eq.true"})
                print("[Success] Soft-cleaned demo records (marked dismissed).")
    except Exception as e:
        print(f"[Error] Cleanup failed: {e}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="TariqMap Demo Data Seed & Clean")
    parser.add_argument("--count", type=int, default=25, help="Number of demo observations to generate (default 25)")
    parser.add_argument("--city", type=str, default="tunis", choices=["tunis", "bizerte", "sousse"], help="City to seed (tunis, bizerte, sousse)")
    parser.add_argument("--clean", action="store_true", help="Remove all demo observations")

    args = parser.parse_args()

    if args.clean:
        cleanup_demo_data()
    else:
        seed_demo_data(count=args.count, city=args.city)
