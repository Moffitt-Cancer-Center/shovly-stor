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

# Per-user quota limits come from InsightIQ, but that's a per-directory quota
# report that hasn't been wired in yet (path -> username mapping unconfirmed).
# Until then, use a single flat default so the dashboard's usage/limit math
# doesn't divide by zero -- NOT a real per-user quota.
ONEFS_DEFAULT_QUOTA_TB = float(os.getenv("ONEFS_DEFAULT_QUOTA_TB", "10"))

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

# Confirmed via GraphQL introspection (--introspect-varonis): resourcesAsync/
# resourcesQueryJob is a file-scan job that returns per-file size, staleness
# (>180 days unaccessed, per isStale) and owner identity -- exactly what's needed
# to compute real per-user usage_tb/stale_data_pct. No pagination fields are
# present in this query, so a single job poll is assumed to return the full
# result set for the scanned file server.
RESOURCES_ASYNC_QUERY = """
query StartResourceQuery {
  resourcesAsync(filter: { type: [FILE] }) {
    jobId
    status
  }
}
"""

RESOURCES_QUERY_JOB = """
query GetResourceSizes($jobId: String!) {
  resourcesQueryJob(jobId: $jobId) {
    jobId
    status
    progress
    results {
      id
      path
      sizeInBytes
      lastAccessed
      lastModified
      isStale
      owner { name accountName }
      dataSource { id name }
    }
  }
}
"""

VARONIS_RESOURCES_POLL_INTERVAL = float(os.getenv("VARONIS_RESOURCES_POLL_INTERVAL", "5"))
VARONIS_RESOURCES_POLL_MAX_ATTEMPTS = int(os.getenv("VARONIS_RESOURCES_POLL_MAX_ATTEMPTS", "60"))

def start_varonis_resources_job(session, token):
    """Kick off the Varonis file-resource scan job (step 1); returns the jobId."""
    result = submit_varonis_graphql(session, token, RESOURCES_ASYNC_QUERY)
    return result["data"]["resourcesAsync"]["jobId"]

def poll_varonis_resources_job(session, token, job_id):
    """Poll the file-resource scan job until it completes; returns the flat list of file results."""
    for _ in range(VARONIS_RESOURCES_POLL_MAX_ATTEMPTS):
        result = submit_varonis_graphql(session, token, RESOURCES_QUERY_JOB, {"jobId": job_id})
        job = result["data"]["resourcesQueryJob"]
        status = (job.get("status") or "").upper()
        if status in ("COMPLETED", "DONE", "SUCCEEDED", "FINISHED"):
            return job.get("results") or []
        if status in ("FAILED", "ERROR", "CANCELLED"):
            raise RuntimeError(f"Varonis resources job {job_id} ended with status {status}")
        time.sleep(VARONIS_RESOURCES_POLL_INTERVAL)
    raise TimeoutError(f"Varonis resources job {job_id} did not complete within "
                        f"{VARONIS_RESOURCES_POLL_MAX_ATTEMPTS * VARONIS_RESOURCES_POLL_INTERVAL:.0f}s")

def get_varonis_usage_by_user(session, token):
    """Run the file-resource scan and aggregate size/staleness per owner account.

    Returns {accountName: {"usage_bytes": int, "stale_bytes": int}}.
    """
    job_id = start_varonis_resources_job(session, token)
    results = poll_varonis_resources_job(session, token, job_id)
    usage_by_user = {}
    for item in results:
        owner = item.get("owner") or {}
        account = owner.get("accountName") or owner.get("name")
        if not account:
            continue
        size = item.get("sizeInBytes") or 0
        entry = usage_by_user.setdefault(account, {"usage_bytes": 0, "stale_bytes": 0})
        entry["usage_bytes"] += size
        if item.get("isStale"):
            entry["stale_bytes"] += size
    return usage_by_user

INTROSPECTION_QUERY = """
query IntrospectionQuery {
  __schema {
    queryType {
      fields {
        name
        description
        args { name type { name kind ofType { name kind } } }
        type { name kind ofType { name kind } }
      }
    }
  }
}
"""

def run_varonis_introspection():
    """Dump the Varonis GraphQL query schema so real queries (e.g. stale-data
    reporting) can be discovered without needing access to the Varonis web UI."""
    session = get_resilient_session()
    token = get_varonis_token(session)
    result = submit_varonis_graphql(session, token, INTROSPECTION_QUERY)
    fields = result.get("data", {}).get("__schema", {}).get("queryType", {}).get("fields", [])
    if not fields:
        print("[-] No query fields returned -- introspection may be disabled on this tenant.")
        return
    print(f"[+] {len(fields)} top-level Varonis GraphQL query fields:")
    for field in fields:
        type_info = field.get("type", {})
        type_name = type_info.get("name") or (type_info.get("ofType") or {}).get("name") or type_info.get("kind")
        print(f"  - {field['name']} -> {type_name}: {field.get('description') or '(no description)'}")

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
        # Real Varonis flow: exchange the API key for a token, then run the
        # resourcesAsync/resourcesQueryJob file-scan job to get per-owner size
        # and staleness totals.
        token = get_varonis_token(session)
        usage_by_user = get_varonis_usage_by_user(session, token)

        if not usage_by_user:
            print("[!] Varonis resource scan returned no owned files -- nothing to write this cycle.")
            return

        # TODO: usage_tb/limit_tb should come from InsightIQ's per-user (per-
        # directory) quota report once that endpoint/path convention is
        # confirmed. For now, usage_tb is derived from Varonis-owned file
        # bytes (a reasonable stand-in) and limit_tb uses a flat placeholder.
        # IOPS has no confirmed per-user source yet, so it's left at 0.
        rows = []
        for username, totals in usage_by_user.items():
            usage_bytes = totals["usage_bytes"]
            stale_bytes = totals["stale_bytes"]
            usage_tb = usage_bytes / 1e12
            stale_pct = (stale_bytes / usage_bytes * 100) if usage_bytes else 0.0
            rows.append((username, usage_tb, ONEFS_DEFAULT_QUOTA_TB, round(stale_pct, 1), 0, "Unknown"))

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
        """, rows)
        conn.commit()
        conn.close()
        print(f"[+] Metrics collection cycle completed successfully ({len(rows)} users).")
    except Exception as e:
        print(f"[-] Error during metrics collection: {e}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Shovly-stor background metrics collector")
    parser.add_argument(
        "--check-connectivity",
        action="store_true",
        help="Test authentication against OneFS and Varonis, then exit (no polling, no DB writes)",
    )
    parser.add_argument(
        "--introspect-varonis",
        action="store_true",
        help="Dump the Varonis GraphQL query schema (to find the real stale-data query) and exit",
    )
    args = parser.parse_args()

    if args.introspect_varonis:
        run_varonis_introspection()
        raise SystemExit(0)

    if args.check_connectivity:
        success = run_connectivity_check()
        raise SystemExit(0 if success else 1)

    init_db()
    while True:
        poll_storage_apis()
        time.sleep(300) # Poll every 5 minutes