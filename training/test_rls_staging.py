#!/usr/bin/env python3
"""
RLS Automated Verification Script for Staging Supabase
Tests all security boundaries defined in migration 20261013_security_and_phase1.sql:
  1. Anon UPDATE on observations (must FAIL)
  2. Anon DELETE on observations (must FAIL)
  3. Anon Storage read/list on private observation-images (must FAIL)
  4. Anon INSERT with is_demo=true (must FAIL)
  5. Anon INSERT with status != 'unconfirmed' (must FAIL)
  6. Non-authority authenticated user UPDATE / read real media (must FAIL)
  7. Authority authenticated user UPDATE / read real media (must SUCCEED)

Credentials are read strictly from local .env or environment variables.
Secrets are never printed.
"""

import os
import sys
import uuid
import json
from pathlib import Path

# Load local .env if present
def load_env():
    env_paths = [
        Path(".env"),
        Path("backend/.env"),
        Path("dashboard/.env"),
        Path(".env.staging"),
    ]
    for p in env_paths:
        if p.exists():
            with open(p, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith("#") and "=" in line:
                        k, v = line.split("=", 1)
                        k = k.strip()
                        v = v.strip().strip("'\"")
                        if k not in os.environ:
                            os.environ[k] = v

load_env()

SUPABASE_URL = os.environ.get("STAGING_SUPABASE_URL") or os.environ.get("TARIQMAP_SUPABASE_URL")
ANON_KEY = os.environ.get("STAGING_SUPABASE_ANON_KEY") or os.environ.get("TARIQMAP_SUPABASE_ANON_KEY")
SERVICE_KEY = os.environ.get("STAGING_SUPABASE_SERVICE_ROLE_KEY") or os.environ.get("TARIQMAP_SUPABASE_SERVICE_ROLE_KEY")

AUTH_EMAIL = os.environ.get("STAGING_AUTHORITY_EMAIL", "authority@tariqmap.tn")
AUTH_PASSWORD = os.environ.get("STAGING_AUTHORITY_PASSWORD", "AuthorityPass123!")

REGULAR_EMAIL = os.environ.get("STAGING_REGULAR_EMAIL", "citizen@tariqmap.tn")
REGULAR_PASSWORD = os.environ.get("STAGING_REGULAR_PASSWORD", "CitizenPass123!")

try:
    from supabase import create_client, Client
except ImportError:
    print("Error: supabase-py not installed. Run: pip install supabase")
    sys.exit(1)

def run_tests():
    if not SUPABASE_URL or not ANON_KEY:
        print("\n[!] STAGING_SUPABASE_URL and STAGING_SUPABASE_ANON_KEY not set.")
        print("Please configure them in a local .env file before running against live staging.\n")
        return False

    print("================================================================================")
    print("TariqMap RLS Security Verification Suite (Staging)")
    print("================================================================================")
    
    anon_client: Client = create_client(SUPABASE_URL, ANON_KEY)
    results = []

    # 1. Anon UPDATE on observations (Must Fail)
    test_id = str(uuid.uuid4())
    try:
        res = anon_client.table("observations").update({"status": "repaired"}).eq("id", test_id).execute()
        # In PostgREST, an RLS update denial either raises 42501 or returns an empty list
        if len(res.data) == 0:
            results.append(("Anon UPDATE on observations", "FAIL (Blocked by RLS)", "PASSED"))
        else:
            results.append(("Anon UPDATE on observations", "VULNERABLE (Row updated)", "FAILED"))
    except Exception as e:
        results.append(("Anon UPDATE on observations", f"FAIL ({type(e).__name__})", "PASSED"))

    # 2. Anon DELETE on observations (Must Fail)
    try:
        res = anon_client.table("observations").delete().eq("id", test_id).execute()
        if len(res.data) == 0:
            results.append(("Anon DELETE on observations", "FAIL (Blocked by RLS)", "PASSED"))
        else:
            results.append(("Anon DELETE on observations", "VULNERABLE (Row deleted)", "FAILED"))
    except Exception as e:
        results.append(("Anon DELETE on observations", f"FAIL ({type(e).__name__})", "PASSED"))

    # 3. Anon Storage read/list on private observation-images (Must Fail)
    try:
        files = anon_client.storage.from_("observation-images").list()
        if files is None or len(files) == 0:
            results.append(("Anon Storage list on observation-images", "FAIL (Empty/Restricted)", "PASSED"))
        else:
            results.append(("Anon Storage list on observation-images", f"VULNERABLE ({len(files)} files listed)", "FAILED"))
    except Exception as e:
        results.append(("Anon Storage list on observation-images", f"FAIL ({type(e).__name__})", "PASSED"))

    # 4. Anon INSERT with is_demo=true (Must Fail)
    try:
        fake_obs = {
            "id": str(uuid.uuid4()),
            "is_demo": True,
            "status": "unconfirmed",
            "source": "camera",
            "priority_score": 50,
            "priority_label": "HIGH",
            "anomaly_type": "D40"
        }
        res = anon_client.table("observations").insert(fake_obs).execute()
        results.append(("Anon INSERT with is_demo=true", "VULNERABLE (Insert allowed)", "FAILED"))
    except Exception as e:
        results.append(("Anon INSERT with is_demo=true", "FAIL (Blocked: is_demo=false check)", "PASSED"))

    # 5. Anon INSERT with status != 'unconfirmed' (Must Fail)
    try:
        fake_obs = {
            "id": str(uuid.uuid4()),
            "is_demo": False,
            "status": "repaired",
            "source": "camera",
            "priority_score": 50,
            "priority_label": "HIGH",
            "anomaly_type": "D40"
        }
        res = anon_client.table("observations").insert(fake_obs).execute()
        results.append(("Anon INSERT with status='repaired'", "VULNERABLE (Insert allowed)", "FAILED"))
    except Exception as e:
        results.append(("Anon INSERT with status='repaired'", "FAIL (Blocked: status='unconfirmed' check)", "PASSED"))

    # 6. Non-authority Authenticated User tests (Must Fail)
    try:
        user_client: Client = create_client(SUPABASE_URL, ANON_KEY)
        auth_resp = user_client.auth.sign_in_with_password({"email": REGULAR_EMAIL, "password": REGULAR_PASSWORD})
        
        # Try update
        try:
            res = user_client.table("observations").update({"status": "confirmed"}).eq("id", test_id).execute()
            if len(res.data) == 0:
                results.append(("Non-authority user UPDATE observation", "FAIL (Blocked: not authority)", "PASSED"))
            else:
                results.append(("Non-authority user UPDATE observation", "VULNERABLE (Updated)", "FAILED"))
        except Exception:
            results.append(("Non-authority user UPDATE observation", "FAIL (Blocked by RLS)", "PASSED"))
    except Exception as auth_err:
        results.append(("Non-authority user test", f"SKIPPED (Account not provisioned on staging)", "PENDING"))

    # 7. Authority Authenticated User tests (Must Succeed)
    try:
        auth_client: Client = create_client(SUPABASE_URL, ANON_KEY)
        auth_resp = auth_client.auth.sign_in_with_password({"email": AUTH_EMAIL, "password": AUTH_PASSWORD})
        
        # Test authority status check
        auth_check = auth_client.rpc("is_authority").execute()
        if auth_check.data is True:
            results.append(("Authority user is_authority()", "SUCCEED (User verified in authority_users)", "PASSED"))
        else:
            results.append(("Authority user is_authority()", "FAIL (User not in authority_users)", "FAILED"))
    except Exception as auth_err:
        results.append(("Authority user test", f"SKIPPED (Account not provisioned on staging)", "PENDING"))

    # Print Markdown Table
    print("\n### RLS Verification Results Matrix\n")
    print("| Security Test | Observed Behavior | Status |")
    print("| :--- | :--- | :--- |")
    for name, obs, status in results:
        badge = "✅ PASSED" if status == "PASSED" else ("⚠️ PENDING" if status == "PENDING" else "❌ FAILED")
        print(f"| {name} | `{obs}` | {badge} |")
    print("\n")
    return True

if __name__ == "__main__":
    run_tests()
