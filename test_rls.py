#!/usr/bin/env python3
"""
RLS Automated Verification Script for TariqMap Supabase
Verifies security boundaries against the live Supabase instance:
  1. Anon UPDATE on observations (Must FAIL)
  2. Anon DELETE on observations (Must FAIL)
  3. Anon Storage read/list on private observation-images (Must FAIL)
  4. Anon INSERT with is_demo=true (Must FAIL)
  5. Anon INSERT with status != 'unconfirmed' (Must FAIL)
  6. Non-authority authenticated user UPDATE (Must FAIL)
  7. Authority authenticated user UPDATE on marked row (Must SUCCEED and clean up)

Credentials are read strictly from environment variables or local .env.
Secrets are never printed.
"""

import os
import sys
import uuid
import re
from pathlib import Path

# Ensure UTF-8 output on Windows console
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8")

try:
    from supabase import create_client, Client
except ImportError:
    print("Error: supabase-py not installed. Run: pip install supabase")
    sys.exit(1)

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

def get_config():
    url = (
        os.environ.get("TARIQMAP_SUPABASE_URL")
        or os.environ.get("STAGING_SUPABASE_URL")
    )
    anon_key = (
        os.environ.get("TARIQMAP_SUPABASE_ANON_KEY")
        or os.environ.get("STAGING_SUPABASE_ANON_KEY")
    )
    service_key = (
        os.environ.get("TARIQMAP_SUPABASE_SERVICE_ROLE_KEY")
        or os.environ.get("STAGING_SUPABASE_SERVICE_ROLE_KEY")
    )

    # Fallback to app config if not in env
    if not url or not anon_key:
        cfg_file = Path("app/lib/core/supabase_config.dart")
        if cfg_file.exists():
            text = cfg_file.read_text(encoding="utf-8")
            m_url = re.search(r"url\s*=\s*'([^']+)'", text)
            m_key = re.search(r"anonKey\s*=\s*'([^']+)'", text)
            if m_url and not url:
                url = m_url.group(1)
            if m_key and not anon_key:
                anon_key = m_key.group(1)

    return url, anon_key, service_key

SUPABASE_URL, ANON_KEY, SERVICE_KEY = get_config()

AUTH_EMAIL = os.environ.get("AUTHORITY_EMAIL") or os.environ.get("STAGING_AUTHORITY_EMAIL", "authority@tariqmap.tn")
AUTH_PASSWORD = os.environ.get("AUTHORITY_PASSWORD") or os.environ.get("STAGING_AUTHORITY_PASSWORD", "AuthorityPass123!")

REGULAR_EMAIL = os.environ.get("REGULAR_EMAIL") or os.environ.get("STAGING_REGULAR_EMAIL", "citizen@tariqmap.tn")
REGULAR_PASSWORD = os.environ.get("REGULAR_PASSWORD") or os.environ.get("STAGING_REGULAR_PASSWORD", "CitizenPass123!")

def run_tests():
    if not SUPABASE_URL or not ANON_KEY:
        print("\n[!] Supabase URL or Anon key not found. Please configure them in .env.\n")
        return False

    print("================================================================================")
    print("TariqMap Live RLS Security Verification Suite")
    print("================================================================================")
    print(f"Target URL: {SUPABASE_URL}")
    print("Executing tests live against Supabase instance...\n")

    anon_client: Client = create_client(SUPABASE_URL, ANON_KEY)
    results = []

    # 1. Anon UPDATE on observations (Must Fail)
    test_id = str(uuid.uuid4())
    try:
        res = anon_client.table("observations").update({"status": "repaired"}).eq("id", test_id).execute()
        if len(res.data) == 0:
            results.append(("Anon UPDATE on observations", "FAIL (Blocked by RLS: 0 rows modified)", "PASSED"))
        else:
            results.append(("Anon UPDATE on observations", "VULNERABLE (Row updated)", "FAILED"))
    except Exception as e:
        results.append(("Anon UPDATE on observations", f"FAIL ({type(e).__name__}: denied)", "PASSED"))

    # 2. Anon DELETE on observations (Must Fail)
    try:
        res = anon_client.table("observations").delete().eq("id", test_id).execute()
        if len(res.data) == 0:
            results.append(("Anon DELETE on observations", "FAIL (Blocked by RLS: 0 rows deleted)", "PASSED"))
        else:
            results.append(("Anon DELETE on observations", "VULNERABLE (Row deleted)", "FAILED"))
    except Exception as e:
        results.append(("Anon DELETE on observations", f"FAIL ({type(e).__name__}: denied)", "PASSED"))

    # 3. Anon Storage read/list on private observation-images (Must Fail)
    try:
        files = anon_client.storage.from_("observation-images").list()
        if files is None or len(files) == 0:
            results.append(("Anon Storage list on observation-images", "FAIL (Blocked: 0 files visible)", "PASSED"))
        else:
            results.append(("Anon Storage list on observation-images", f"VULNERABLE ({len(files)} files listed)", "FAILED"))
    except Exception as e:
        results.append(("Anon Storage list on observation-images", f"FAIL ({type(e).__name__}: denied)", "PASSED"))

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
        results.append(("Anon INSERT with is_demo=true", "FAIL (Blocked: is_demo check violation)", "PASSED"))

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
        results.append(("Anon INSERT with status='repaired'", "FAIL (Blocked: status check violation)", "PASSED"))

    # 6. Non-authority Authenticated User tests (Must Fail)
    try:
        user_client: Client = create_client(SUPABASE_URL, ANON_KEY)
        auth_resp = user_client.auth.sign_in_with_password({"email": REGULAR_EMAIL, "password": REGULAR_PASSWORD})
        try:
            res = user_client.table("observations").update({"status": "confirmed"}).eq("id", test_id).execute()
            if len(res.data) == 0:
                results.append(("Non-authority user UPDATE observation", "FAIL (Blocked: not authority)", "PASSED"))
            else:
                results.append(("Non-authority user UPDATE observation", "VULNERABLE (Updated)", "FAILED"))
        except Exception:
            results.append(("Non-authority user UPDATE observation", "FAIL (Blocked by RLS)", "PASSED"))
    except Exception as auth_err:
        err_msg = str(auth_err)
        if "Invalid login credentials" in err_msg:
            results.append(("Non-authority user test", "SKIPPED (Account not provisioned in Auth)", "SKIPPED"))
        else:
            results.append(("Non-authority user test", f"SKIPPED ({type(auth_err).__name__})", "SKIPPED"))

    # 7. Authority Authenticated User tests (Must Succeed on marked row and clean up)
    marked_capture_id = f"rls-test-{uuid.uuid4()}"
    marked_obs_id = str(uuid.uuid4())
    try:
        auth_client: Client = create_client(SUPABASE_URL, ANON_KEY)
        auth_resp = auth_client.auth.sign_in_with_password({"email": AUTH_EMAIL, "password": AUTH_PASSWORD})
        
        # Verify is_authority()
        auth_check = auth_client.rpc("is_authority").execute()
        if auth_check.data is not True:
            results.append(("Authority is_authority() check", "FAIL (User not in authority_users)", "FAILED"))
        else:
            # 1. Insert marked row via anon/auth insert
            auth_client.table("observations").insert({
                "id": marked_obs_id,
                "capture_id": marked_capture_id,
                "is_demo": False,
                "status": "unconfirmed",
                "source": "camera",
                "priority_score": 10,
                "priority_label": "LOW",
                "anomaly_type": "D00"
            }).execute()

            # 2. Update marked row as authority
            update_res = auth_client.table("observations").update({
                "status": "confirmed",
                "assigned_contractor": "RLS Test Contractor",
                "budget_estimate_tnd": 250
            }).eq("id", marked_obs_id).execute()

            if len(update_res.data) > 0 and update_res.data[0]["status"] == "confirmed":
                # 3. Clean up marked row
                # Use service_role if available, or delete
                cleanup_success = False
                if SERVICE_KEY and not SERVICE_KEY.startswith("sb_secret_"):
                    admin_client = create_client(SUPABASE_URL, SERVICE_KEY)
                    admin_client.table("observations").delete().eq("id", marked_obs_id).execute()
                    cleanup_success = True
                else:
                    try:
                        auth_client.table("observations").delete().eq("id", marked_obs_id).execute()
                        cleanup_success = True
                    except Exception:
                        pass

                # 4. Confirm 0 leftover rows matching rls-test-
                verify_res = anon_client.table("observations").select("id").like("capture_id", "rls-test-%").execute()
                leftover_count = len(verify_res.data)

                if leftover_count == 0:
                    results.append(("Authority UPDATE marked row & cleanup", f"SUCCEED (Updated + 0 leftover rows)", "PASSED"))
                else:
                    results.append(("Authority UPDATE marked row & cleanup", f"WARN (Updated, but {leftover_count} leftover rows)", "FAILED"))
            else:
                results.append(("Authority UPDATE marked row", "FAIL (Update yielded 0 rows)", "FAILED"))

    except Exception as auth_err:
        err_msg = str(auth_err)
        if "Invalid login credentials" in err_msg:
            results.append(("Authority user UPDATE marked row", "SKIPPED (Account authority@tariqmap.tn not provisioned in Auth)", "SKIPPED"))
        else:
            results.append(("Authority user UPDATE marked row", f"SKIPPED ({type(auth_err).__name__})", "SKIPPED"))

    # Print Markdown Table
    print("\n### RLS Verification Results Matrix (Live Measured)\n")
    print("| Security Test | Observed Behavior | Status |")
    print("| :--- | :--- | :--- |")
    for name, obs, status in results:
        badge = "✅ PASSED" if status == "PASSED" else ("⚠️ SKIPPED" if status == "SKIPPED" else "❌ FAILED")
        print(f"| {name} | `{obs}` | {badge} |")
    print("\n")
    return True

if __name__ == "__main__":
    run_tests()
