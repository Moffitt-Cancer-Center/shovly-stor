import argparse
import os
import time
import sqlite3
import requests
from dotenv import load_dotenv
from requests.adapters import HTTPAdapter, Retry

load_dotenv()

ONEFS_URL = os.getenv("ONEFS_URL", "https://isilon.local:8080")
USER = os.getenv("METRICS_USER", "readonly-metrics-user")
PASSWORD = os.getenv("METRICS_PASSWORD", "")

# Varonis DatAdvantage authenticates via API key only, not username/password
VARONIS_URL = os.getenv("VARONIS_URL", "https://varonis.local/api")
VARONIS_API_KEY = os.getenv("VARONIS_API_KEY", "")

# Internal appliances often present self-signed certs; allow opt-out per environment
VERIFY_TLS = os.getenv("VERIFY_TLS", "true").strip().lower() not in ("false", "0", "no")

DB_PATH = os.getenv("SHOVLY_DB_PATH", "data/Shovly-stor")

def get_db():
    conn = sqlite3.connect(DB_PATH)
    # Enable WAL mode for high concurrency between web app and collector
    conn.execute("PRAGMA journal_mode=WAL;")
    return conn

def init_db():
    conn = get_db()
    conn.execute("""
        CREATE TABLE IF NOT EXISTS metrics (
            username TEXT PRIMARY KEY,
            usage_tb REAL,
            limit_tb REAL,
            stale_data_pct REAL,
            iops INTEGER,
            grace_period TEXT
        )
    """)
    conn.commit()
    conn.close()

def get_resilient_session():
    session = requests.Session()
    retries = Retry(total=3, backoff_factor=1, status_forcelist=[500, 502, 503, 504])
    session.mount('https://', HTTPAdapter(max_retries=retries))
    return session

def check_onefs_connectivity(session):
    """Perform a real authenticated request against OneFS and report reachability."""
    try:
        resp = session.get(
            f"{ONEFS_URL}/platform/1/quota/quotas",
            auth=(USER, PASSWORD),
            verify=VERIFY_TLS,
            timeout=10,
        )
        if resp.status_code == 401:
            return False, "Reachable, but authentication failed (check METRICS_USER/METRICS_PASSWORD)"
        resp.raise_for_status()
        return True, f"OK (HTTP {resp.status_code})"
    except requests.exceptions.RequestException as e:
        return False, str(e)

def check_varonis_connectivity(session):
    """Perform a real authenticated request against Varonis and report reachability."""
    try:
        headers = {"Authorization": f"Bearer {VARONIS_API_KEY}"}
        resp = session.get(f"{VARONIS_URL}/statistics", headers=headers, verify=VERIFY_TLS, timeout=10)
        if resp.status_code == 401:
            return False, "Reachable, but authentication failed (check VARONIS_API_KEY)"
        resp.raise_for_status()
        return True, f"OK (HTTP {resp.status_code})"
    except requests.exceptions.RequestException as e:
        return False, str(e)

def run_connectivity_check():
    session = get_resilient_session()
    print("[*] Testing OneFS connectivity...")
    onefs_ok, onefs_detail = check_onefs_connectivity(session)
    print(f"    {'[+] OneFS OK' if onefs_ok else '[-] OneFS FAILED'}: {onefs_detail}")

    print("[*] Testing Varonis connectivity...")
    varonis_ok, varonis_detail = check_varonis_connectivity(session)
    print(f"    {'[+] Varonis OK' if varonis_ok else '[-] Varonis FAILED'}: {varonis_detail}")

    return onefs_ok and varonis_ok

def poll_storage_apis():
    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Starting metrics collection cycle...")
    session = get_resilient_session()
    
    try:
        # Example API Call to OneFS Quotas (Dummy data mapped for illustration)
        # response = session.get(f"{ONEFS_URL}/platform/1/quota/quotas", auth=(USER, PASSWORD), verify=False, timeout=10)

        # Example API Call to Varonis DatAdvantage (API key auth, not username/password)
        # headers = {"Authorization": f"Bearer {VARONIS_API_KEY}"}
        # response = session.get(f"{VARONIS_URL}/statistics", headers=headers, verify=False, timeout=10)

        # Simulated payload representing processed aggregation of Varonis + InsightIQ
        simulated_data = [
            ("jdoe", 4.2, 5.0, 35.0, 125, "None"),
            ("asmith", 8.9, 10.0, 12.0, 310, "4 days"),
            ("bwayne", 14.5, 15.0, 65.0, 42, "None")
        ]
        
        conn = get_db()
        conn.executemany("""
            INSERT INTO metrics (username, usage_tb, limit_tb, stale_data_pct, iops, grace_period)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(username) DO UPDATE SET
                usage_tb=excluded.usage_tb,
                limit_tb=excluded.limit_tb,
                stale_data_pct=excluded.stale_data_pct,
                iops=excluded.iops,
                grace_period=excluded.grace_period
        """, simulated_data)
        conn.commit()
        conn.close()
        print("[+] Metrics collection cycle completed successfully.")
    except Exception as e:
        print(f"[-] Error during metrics collection: {e}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Shovly-stor background metrics collector")
    parser.add_argument(
        "--check-connectivity",
        action="store_true",
        help="Test authentication against OneFS and Varonis, then exit (no polling, no DB writes)",
    )
    args = parser.parse_args()

    if args.check_connectivity:
        success = run_connectivity_check()
        raise SystemExit(0 if success else 1)

    init_db()
    while True:
        poll_storage_apis()
        time.sleep(300) # Poll every 5 minutes