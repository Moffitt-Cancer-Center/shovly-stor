import argparse
import os
import time
import sqlite3
import requests
import urllib3
from dotenv import load_dotenv
from requests.adapters import HTTPAdapter, Retry

load_dotenv(override=True)  # .env must win over any stray shell-exported vars (e.g. $USER)

ONEFS_URL = os.getenv("ONEFS_URL", "https://isilon.local:8080")
# METRICS_USER must be a real InsightIQ account (InsightIQ uses per-user accounts,
# not a generic shared service-account name) -- configure a dedicated read-only
# account for this in .env.
USER = os.getenv("METRICS_USER", "")
PASSWORD = os.getenv("METRICS_PASSWORD", "")

# Varonis authenticates via API key only, not username/password: the key is
# exchanged for a short-lived bearer token, which then authorizes GraphQL calls.
# VARONIS_URL must be the tenant base URL only -- strip any leftover /api suffix
# (VARONIS_TOKEN_PATH/VARONIS_GRAPHQL_PATH already include /api) to avoid /api/api/...
VARONIS_URL = os.getenv("VARONIS_URL", "https://varonis.local").rstrip("/")
if VARONIS_URL.endswith("/api"):
    VARONIS_URL = VARONIS_URL[: -len("/api")]
VARONIS_API_KEY = os.getenv("VARONIS_API_KEY", "")
VARONIS_TOKEN_PATH = os.getenv("VARONIS_TOKEN_PATH", "/api/authentication/api_keys/token")
VARONIS_GRAPHQL_PATH = os.getenv("VARONIS_GRAPHQL_PATH", "/api/graphql")

# Confirmed via browser DevTools: InsightIQ authenticates with a session cookie
# ("insightiq_auth", a JWT) obtained from a login endpoint -- NOT per-request HTTP
# Basic auth. Confirmed via curl probing: GET .../auth/session returns
# {"message": "Invalid token or Session does not exist."} (a session-check/whoami
# route, not the login route), while GET .../auth/login returns 405 Method Not
# Allowed (the route exists but only accepts POST) -- so /auth/login is the login
# endpoint. Request body shape (field names) is still unconfirmed -- adjust the
# json= payload in get_insightiq_session() below once you've captured it (see
# README Troubleshooting).
ONEFS_LOGIN_PATH = os.getenv("ONEFS_LOGIN_PATH", "/insightiq/rest/security-iam/v1/auth/login")

# Confirmed via browser DevTools Network tab against the InsightIQ web UI:
# GET /insightiq/rest/reporting/v1/capacity/graph_data?cluster=<id>&start_time=<epoch>&end_time=<epoch>
# ONEFS_CLUSTER_ID is the cluster GUID InsightIQ reports on; find it in the same
# Network tab capture (the "cluster" query param) if it differs per environment.
ONEFS_CLUSTER_ID = os.getenv("ONEFS_CLUSTER_ID", "")
ONEFS_CHECK_PATH = os.getenv("ONEFS_CHECK_PATH", "/insightiq/rest/reporting/v1/capacity/graph_data")

# The insightiq_auth JWT reportedly carries a "csrf" claim; some cookie-session
# APIs require that value echoed back as a header on every request (double-submit
# CSRF protection), which would explain a 401 on the reporting call even after a
# successful login. Header name is unconfirmed -- check the working request in
# DevTools and override here if it differs (see README Troubleshooting).
ONEFS_CSRF_HEADER = os.getenv("ONEFS_CSRF_HEADER", "X-CSRF-Token")

# Internal appliances often present self-signed certs; allow opt-out per environment
VERIFY_TLS = os.getenv("VERIFY_TLS", "true").strip().lower() not in ("false", "0", "no")
if not VERIFY_TLS:
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

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

def get_insightiq_session(session):
    """Log in to InsightIQ so `session` carries the insightiq_auth cookie for subsequent calls.

    Returns the CSRF token value if one was found in the login response's cookies
    or JSON body, else None.

    ONEFS_LOGIN_PATH/payload format are unconfirmed -- capture the real login POST
    from DevTools and adjust this if it 404s/401s.
    """
    resp = session.post(
        f"{ONEFS_URL}{ONEFS_LOGIN_PATH}",
        json={"username": USER, "password": PASSWORD},
        verify=VERIFY_TLS,
        timeout=10,
    )
    resp.raise_for_status()
    if "insightiq_auth" not in session.cookies:
        raise ValueError("Login succeeded but no insightiq_auth cookie was set -- check ONEFS_LOGIN_PATH/payload")

    for name, value in session.cookies.items():
        if "csrf" in name.lower() or "xsrf" in name.lower():
            return value
    try:
        body = resp.json()
    except ValueError:
        body = {}
    for key in ("csrf", "csrfToken", "csrf_token"):
        if key in body:
            return body[key]
    return None

def check_onefs_connectivity(session):
    """Log in to InsightIQ and request the reporting API to confirm reachability/auth."""
    if not ONEFS_CLUSTER_ID:
        return False, "ONEFS_CLUSTER_ID is not set -- required query param for the InsightIQ reporting API"
    now = int(time.time())
    params = {"cluster": ONEFS_CLUSTER_ID, "start_time": now - 3600, "end_time": now}
    try:
        csrf_token = get_insightiq_session(session)
        headers = {ONEFS_CSRF_HEADER: csrf_token} if csrf_token else {}
        resp = session.get(
            f"{ONEFS_URL}{ONEFS_CHECK_PATH}",
            params=params,
            headers=headers,
            verify=VERIFY_TLS,
            timeout=10,
        )
        if resp.status_code == 401:
            if csrf_token:
                return False, f"Reachable, login succeeded, but {ONEFS_CHECK_PATH} still returned 401 with a {ONEFS_CSRF_HEADER} header sent -- check the header name/value via DevTools, or the account's role permissions"
            return False, f"Reachable, login succeeded, but {ONEFS_CHECK_PATH} returned 401 -- no CSRF token was found on the login response; capture the required header from a working request in DevTools and set ONEFS_CSRF_HEADER, or check the account's role permissions"
        if resp.status_code == 404:
            return False, f"Reachable, but {ONEFS_CHECK_PATH} returned 404 -- wrong path/port for this appliance, set ONEFS_CHECK_PATH"
        resp.raise_for_status()
        return True, f"OK (HTTP {resp.status_code})"
    except requests.exceptions.RequestException as e:
        return False, str(e)
    except ValueError as e:
        return False, str(e)

def get_varonis_token(session):
    """Exchange the Varonis API key for a short-lived bearer token (step 1 of 3)."""
    resp = session.post(
        f"{VARONIS_URL}{VARONIS_TOKEN_PATH}",
        headers={"x-api-key": VARONIS_API_KEY},
        data={"grant_type": "varonis_custom"},
        verify=VERIFY_TLS,
        timeout=10,
    )
    resp.raise_for_status()
    payload = resp.json()
    for key in ("access_token", "accessToken", "token"):
        if key in payload:
            return payload[key]
    raise KeyError(f"Varonis token response did not contain a recognized token field: {list(payload.keys())}")

def submit_varonis_graphql(session, token, query, variables=None):
    """Submit a GraphQL query/job to Varonis (step 2 of 3); returns the parsed JSON response."""
    resp = session.post(
        f"{VARONIS_URL}{VARONIS_GRAPHQL_PATH}",
        headers={"Authorization": f"Bearer {token}"},
        json={"query": query, "variables": variables or {}},
        verify=VERIFY_TLS,
        timeout=15,
    )
    resp.raise_for_status()
    return resp.json()

EVENTS_QUERY_JOB = """
query EventsQueryJob($jobId: ID!) {
  eventsQueryJob(jobId: $jobId) {
    jobId
    results {
      actor { email }
      affectedObjectName
      id
      operation
      status
    }
  }
}
"""

def poll_varonis_job(session, token, job_id):
    """Poll a previously submitted Varonis job for results (step 3 of 3)."""
    return submit_varonis_graphql(session, token, EVENTS_QUERY_JOB, {"jobId": job_id})

def check_varonis_connectivity(session):
    """Verify the Varonis API key can be exchanged for a bearer token (real auth check)."""
    try:
        get_varonis_token(session)
        return True, "OK (API key exchanged for bearer token)"
    except requests.exceptions.HTTPError as e:
        if e.response is not None and e.response.status_code in (401, 403):
            return False, "Reachable, but authentication failed (check VARONIS_API_KEY)"
        return False, str(e)
    except requests.exceptions.RequestException as e:
        return False, str(e)
    except KeyError as e:
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
        # Example InsightIQ capacity call: log in for the insightiq_auth cookie,
        # then request the reporting API on the same session (no Basic auth).
        # get_insightiq_session(session)
        # params = {"cluster": ONEFS_CLUSTER_ID, "start_time": start_epoch, "end_time": end_epoch}
        # response = session.get(f"{ONEFS_URL}{ONEFS_CHECK_PATH}", params=params, verify=VERIFY_TLS, timeout=10)

        # Example real Varonis flow: exchange API key for a token, submit a
        # GraphQL query to get a jobId, then poll poll_varonis_job() for results.
        # token = get_varonis_token(session)
        # job = submit_varonis_graphql(session, token, MY_QUERY)
        # results = poll_varonis_job(session, token, job["jobId"])

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