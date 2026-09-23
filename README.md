# Shovly-stor Storage Metrics Suite

Shovly-stor is an enterprise-grade storage monitoring and analytics platform designed to aggregate metrics from Dell InsightIQ (OneFS), authenticated via a dedicated read-only InsightIQ account, and Varonis DatAdvantage, authenticated via a dedicated API key.

It decouples live API polling from user interactions by utilizing a dedicated background collector daemon and a local SQLite cache (running in WAL mode), providing zero-latency command-line summaries on SSH login and a secure administrative web dashboard equipped with dynamic Chart.js drill-downs.

## Features & Architecture

- **Background Collector Daemon (`collector.py`)**: Periodically polls storage APIs on a fixed interval, handles network timeouts and retries, and securely commits records to the local cache.
- **Database Concurrency (WAL Mode)**: SQLite configured with Write-Ahead Logging to allow simultaneous reads from the web application and writes from the background worker without lock conflicts.
- **Secure Secrets Management (`.env`)**: Keeps plaintext credentials out of the source code using strict file-permissioned environment configurations (`chmod 600`).
- **SSH Login Terminal Summary**: Instantly prints quota limits, storage capacity usage, stale data percentages, and active IOPS load using rich formatting via an interactive shell hook (`/etc/profile.d/show_storage.sh`).
- **Production FastAPI Web Dashboard**: Features HTTP Basic Authentication for administrators, an uptime health check route (`/healthz`), and a master overview table.
- **Interactive Drill-Down Modals**: Powered by Chart.js, rendering visual breakdowns of Data Temperature (Active vs. Stale data >180 days) and Quota Capacity Usage (Used vs. Free storage).

## Project Structure

```
/opt/shovly-stor/
├── main.py                  # FastAPI backend server with HTTP Basic Auth & /healthz
├── collector.py             # Background polling daemon worker script
├── .env                     # Production environment variables (restricted permissions)
├── templates/
│   └── dashboard.html       # Chart.js web frontend UI & drill-down modal
├── data/
│   └── Shovly-stor          # Central SQLite cache database (WAL mode enabled)
└── venv/                    # Isolated Python virtual environment
/usr/local/bin/
└── user_storage_cli.py      # Terminal CLI script for SSH logins
/etc/profile.d/
└── show_storage.sh          # Interactive login hook script
/etc/systemd/system/
├── shovly-web.service       # Systemd service for the web interface
└── shovly-collector.service # Systemd service for the background polling daemon
```

The source repository mirrors this layout directly: `templates/dashboard.html`, `requirements.txt`, `shovly-web.service` and `shovly-collector.service` (unit file templates), and `install.sh` all live at the repo root and are copied into place by the installer.

## Installation & Setup

### 1. Prerequisites

- A Linux server (Ubuntu/Debian/RHEL-based) with root or sudo privileges.
- Network access to your Dell OneFS API endpoint using a dedicated read-only InsightIQ account (`METRICS_USER`/`METRICS_PASSWORD`).
- Network access to your Varonis DatAdvantage API endpoint using a valid API key (username/password is not supported by Varonis).

### 2. Automated Installation

Clone or copy the project files to your deployment server directory, then run the automated installation script:

```bash
sudo chmod +x install.sh
sudo ./install.sh
```

The installer will:

- Install system package dependencies (`python3`, `python3-venv`, `sqlite3`).
- Set up the `/opt/shovly-stor/` application directory structure.
- Configure an isolated Python virtual environment and install all requirements from `requirements.txt` (`fastapi`, `uvicorn`, `requests`, `rich`, `jinja2`, `python-dotenv`).
- Provision a template `.env` secrets file at `/opt/shovly-stor/.env` and restrict permissions to `chmod 600`.
- Register the SSH interactive login script hook at `/etc/profile.d/show_storage.sh`.
- Register, enable, and start both systemd services (`shovly-web.service` and `shovly-collector.service`).

## Configuration

Before relying on live API scraping, update the credentials and URLs in the secure environment file:

```bash
sudo nano /opt/shovly-stor/.env
```

```
ONEFS_URL=https://isilon.local:8080
METRICS_USER=YourInsightIQUsername
METRICS_PASSWORD=YourSecureProductionPasswordHere
ONEFS_CLUSTER_ID=YourInsightIQClusterGuid
VARONIS_URL=https://varonis.local
VARONIS_API_KEY=YourVaronisApiKeyHere
ADMIN_USER=admin
ADMIN_PASSWORD=SuperSecretAdminPassword
```

`METRICS_USER` / `METRICS_PASSWORD` authenticate only against the OneFS API. InsightIQ uses real per-user accounts (not a generic shared "service account" username) -- use a dedicated read-only account. Varonis does not accept username/password credentials — `VARONIS_API_KEY` is exchanged for a short-lived bearer token (see [Varonis Authentication](#varonis-authentication) below). `VARONIS_URL` is your tenant's base URL (e.g. `https://your-tenant.varonis.io`), without an `/api` suffix.

After modifying the file, restart the background collector and web services to apply changes:

```bash
sudo systemctl restart shovly-collector.service shovly-web.service
```

## Local Development

To run the stack locally without the full installer:

```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

Create a `.env` file in the project root (it is not generated for you outside of `install.sh`) with at least the admin dashboard credentials:

```
ADMIN_USER=admin
ADMIN_PASSWORD=ChooseYourOwnLocalPassword
ONEFS_URL=https://isilon.local:8080
METRICS_USER=YourInsightIQUsername
METRICS_PASSWORD=YourSecureProductionPasswordHere
ONEFS_CLUSTER_ID=YourInsightIQClusterGuid
VARONIS_URL=https://varonis.local
VARONIS_API_KEY=YourVaronisApiKeyHere
```

Without this file, `main.py` falls back to the hardcoded defaults `admin` / `secret`.

```bash
python collector.py &          # populates data/Shovly-stor
uvicorn main:app --reload
```

The collector and web server both read from `data/Shovly-stor` relative to the working directory by default; set the `SHOVLY_DB_PATH` environment variable to point them (and `user_storage_cli.py`) at a different cache file if needed.

## Usage

### 1. Command-Line Utility (SSH Login)

Whenever a user logs in via an interactive SSH session, the system hook instantly triggers `user_storage_cli.py`, outputting a clean summary of their specific storage allocation, grace periods, stale data stats, and active IOPS load with a strict 2-second fallback timeout to prevent login blocking.

### 2. Web Dashboard

Access the administrative overview via your browser:

- **URL**: `http://<server-ip>:8000`
- **Authentication**: Enter the administrator credentials configured in your `.env` file (`ADMIN_USER` / `ADMIN_PASSWORD`).
- **Global Overview**: Inspect all users, current usage in TB, quota limits, and red flags for users exceeding 90% capacity thresholds.
- **Drill-Down Charts**: Click "Drill Down" on any row to open the interactive modal containing:
  - **Data Temperature Pie Chart**: Active vs. Stale (>180 days) distribution.
  - **Quota Usage Bar Chart**: Consumed vs. Available storage space.

### 3. Health Monitoring & Service Management

You can verify application health using the built-in endpoint:

```bash
curl -u admin:SuperSecretAdminPassword http://localhost:8000/healthz
```

Manage systemd background daemons with standard controls:

```bash
# Check status of web UI and background collector
sudo systemctl status shovly-web.service shovly-collector.service

# Restart services
sudo systemctl restart shovly-web.service
sudo systemctl restart shovly-collector.service

# View live daemon logs
journalctl -u shovly-collector.service -f
```

## Troubleshooting

### Testing Varonis/InsightIQ connectivity

The collector's polling cycle currently writes simulated demo data on every run — it does not yet call the live APIs — so there is nothing to observe by watching the dashboard. To independently verify authentication and network reachability against both OneFS and Varonis, run the collector's built-in connectivity check, which performs a real authenticated request to each API and exits without touching the database:

```bash
cd /opt/shovly-stor
sudo venv/bin/python collector.py --check-connectivity
```

It reports `OK`, an authentication failure (bad credentials/API key), or a network/TLS error for each service independently. If your OneFS or Varonis endpoint uses a self-signed certificate, set `VERIFY_TLS=false` in `.env` (accepted only for trusted internal networks).

**`ONEFS_CHECK_PATH` (`/insightiq/rest/reporting/v1/capacity/graph_data` by default) is InsightIQ's confirmed reporting API path** — captured from the browser DevTools Network tab against the InsightIQ web UI, not the PowerScale/OneFS Platform API (PAPI). Your InsightIQ appliance host serves the Angular reporting UI itself (`<title>InsightIQ</title>`, a `login` JS bundle), a separate product from raw PowerScale cluster nodes — PAPI paths like `/platform/1/quota/quotas` will always 404 there regardless of credentials.

The real endpoint requires a `cluster` query param (the cluster GUID InsightIQ reports on) plus a `start_time`/`end_time` epoch window:

```
GET /insightiq/rest/reporting/v1/capacity/graph_data?cluster=<cluster-guid>&start_time=<epoch>&end_time=<epoch>
```

Set the cluster GUID in `.env`:

```
ONEFS_CLUSTER_ID=YourInsightIQClusterGuid
```

**Confirmed via DevTools: InsightIQ authenticates with a session cookie (`insightiq_auth`, a JWT), not per-request HTTP Basic auth.** The cookie is issued by a login endpoint and carries the user's role (e.g. `read-only`) and a `csrf` claim. `collector.py` now performs a login step (`get_insightiq_session()`) with `METRICS_USER`/`METRICS_PASSWORD` before calling the reporting API, reusing the resulting cookie on the same `requests.Session`.

**`ONEFS_LOGIN_PATH` (`/insightiq/rest/security-iam/v1/auth/login` by default) is the confirmed login endpoint; its request body shape (field names) is not yet confirmed.** This was narrowed down via curl: `GET .../auth/session` (with `-u user:pass`) returns `{"message": "Invalid token or Session does not exist."}` -- a session-check/whoami route, not a login route -- while `GET .../auth/login` returns `405 Method Not Allowed`, confirming the route exists but only accepts `POST`. `get_insightiq_session()` currently POSTs `{"username": ..., "password": ...}` as JSON — adjust the payload in `collector.py` once you've captured the real body (see below). Never paste the resulting `insightiq_auth` cookie/JWT value anywhere (chat, commits, logs) — it's a live credential equivalent to a session password; if one is ever exposed, log out of that InsightIQ session or wait for it to expire.

If the appliance presents a self-signed certificate (curl reports `SSL certificate problem: self signed certificate`), set `VERIFY_TLS=false` in `.env` (accepted only for trusted internal networks) -- otherwise every request from `collector.py` will fail with an SSL verification error before it even reaches the login logic.

To capture the request body shape in DevTools: open the Network tab, submit the InsightIQ login form, click the `auth/login` request in the list, and open its **Payload** (Chrome) or **Request** (Firefox) tab — it shows the exact field names sent (e.g. `username`/`password` vs. `user`/`pass`, and whether it's JSON or form-encoded). Share those field *names* (redact the password value) so the payload in `get_insightiq_session()` can be corrected if needed.

**Login succeeds (no exception) but the reporting call still returns 401** -- this points at CSRF, not bad credentials: the `insightiq_auth` JWT reportedly carries a `csrf` claim, and Angular apps commonly require that value echoed back as a request header (double-submit CSRF protection) on every subsequent call. `get_insightiq_session()` now looks for a CSRF value in a `csrf`/`xsrf`-named cookie or in the login response's JSON body, and sends it back via the `ONEFS_CSRF_HEADER` header (`X-CSRF-Token` by default) on the reporting request. If the connectivity check still 401s after this:

- In DevTools, find a working (200) reporting request and check its **Request Headers** for any non-standard header (e.g. `X-XSRF-TOKEN`, `csrf-token`) — set `ONEFS_CSRF_HEADER` in `.env` to match if it differs from `X-CSRF-Token`.
- Confirm the login response actually contains a CSRF value in a cookie or JSON field named `csrf`/`csrfToken`/`csrf_token`; adjust `get_insightiq_session()` if it uses a different field name.
- Rule out a permissions issue: confirm the read-only account's role is actually allowed to call `ONEFS_CHECK_PATH` and not just view the UI.

If you need to override the reporting path or point at a different InsightIQ deployment:

- Override it per-environment without editing code: set `ONEFS_CHECK_PATH` in `.env`.
- Consult Dell's official "InsightIQ REST API Guide" for your installed version.
- Check whether the appliance exposes a Swagger/OpenAPI UI (commonly at `/apidocs`, `/swagger`, or `/api-docs`).

The Varonis check is a confirmed, real auth request (see below), so a failure there reflects an actual credentials/network problem, not a guessed path.

### `.env` values being ignored / wrong username showing up

`python-dotenv`'s `load_dotenv()` does not override variables already present in the process environment by default — if `METRICS_USER` (or any other var this app reads) was ever exported in your shell (manually, via a profile script, etc.), that stray value silently wins over `.env`, even under `sudo`. `collector.py` and `main.py` now call `load_dotenv(override=True)` so `.env` is always authoritative. If you still see unexpected values, run `env | grep -E 'METRICS_|VARONIS_|ADMIN_|ONEFS_'` to check for leftover exports and `unset` them.

### Varonis Authentication

Varonis uses a 3-step, job-based GraphQL flow — not simple Bearer-with-API-key:

1. **Get a token**: `POST {VARONIS_URL}/api/authentication/api_keys/token` with header `x-api-key: <VARONIS_API_KEY>` and form-urlencoded body `grant_type=varonis_custom`. Returns a short-lived bearer token. Implemented as `get_varonis_token()` in `collector.py`.
2. **Submit a query**: `POST {VARONIS_URL}/api/graphql` with `Authorization: Bearer <token>` and a GraphQL query body describing the data you want. Returns a `jobId`. Implemented as `submit_varonis_graphql()`.
3. **Poll for results**: `POST {VARONIS_URL}/api/graphql` again with the `resourcesQueryJob($jobId: ID!)` query and the `jobId` from step 2 to retrieve results once the job completes. Implemented as `poll_varonis_resources_job()`.

`collector.py --check-connectivity` only exercises step 1 (token exchange) to confirm the API key and network path are valid. The real polling cycle (`poll_storage_apis()`) runs the full 3-step flow via `get_varonis_usage_by_user()`, scanning file resources and aggregating size/staleness per owner.

By default this scans every file resource the API key can see across every data source. To scope it down to a specific data source and set of paths (defaults already match the OneFS zones this project cares about), set in `.env`:

```
VARONIS_DATA_SOURCE_NAME=ISLN22
VARONIS_DATA_SOURCE_TYPE=DELL_EMC_POWER_SCALE_ONE_FS_ISILON
VARONIS_PATH_PREFIXES=/ifs/zones/cln01/data/apps,/ifs/zones/cln01/data/dept,/ifs/zones/cln01/data/project,/ifs/zones/cln01/data/systems,/ifs/zones/res01/data/apps,/ifs/zones/res01/data/archive,/ifs/zones/res01/data/dept,/ifs/zones/res01/data/lab,/ifs/zones/res01/data/project,/ifs/zones/res01/data/research,/ifs/zones/res01/data/systems,/ifs/zones/vs1/data/apps
```

`VARONIS_DATA_SOURCE_NAME`/`VARONIS_DATA_SOURCE_TYPE` are resolved to a numeric data source id (via `dataSourcesAsync`/`resolve_varonis_data_source_id()`) and filtered **server-side** in `resourcesAsync`'s `where` clause, using `dataSource: { id: { in: [...] } }` -- confirmed against Varonis' own official sample queries in `docs/varonis/ExampleScripts/Gql/*.gql`, which all filter this way (by id, never by name). Those same official samples don't filter `resourcesAsync` by path/folder at all, so `VARONIS_PATH_PREFIXES` stays a **client-side** filter in `get_varonis_usage_by_user()` (substring match against each result's `path`, not strict prefix, since the exact text Varonis returns before `/ifs/...` isn't confirmed) -- this isn't a workaround, it reflects how Varonis' own tooling does it too. Leave any of the three variables blank to skip that check. Use `--explore-type DataSourceType` to see all valid `VARONIS_DATA_SOURCE_TYPE` enum values for your tenant.

### Dashboard login (`admin`/password) doesn't work

`main.py` reads `ADMIN_USER`/`ADMIN_PASSWORD` from `.env` via `load_dotenv()`, which only finds the file if it exists in the process's working directory:

- Under systemd, `WorkingDirectory=/opt/shovly-stor` is set for you, so confirm `/opt/shovly-stor/.env` exists and contains the values you expect.
- After editing `.env`, you must restart the service (`sudo systemctl restart shovly-web.service`) — changes are only read at process startup.
- When running locally per the [Local Development](#local-development) steps, you must create your own `.env` in the directory you launch `uvicorn` from; without it, the credentials silently fall back to `admin` / `secret`.

### Browser shows "Internal Server Error" on the dashboard

This is almost always caused by the `metrics` table not existing yet in the SQLite cache. `dashboard.html` calls `/api/users` on page load, and that route raises an uncaught `sqlite3.OperationalError: no such table: metrics` (surfaced by FastAPI as a generic 500) if `collector.py`'s daemon mode has never run to create the table via `init_db()` -- e.g. right after a fresh install/clone, before `data/Shovly-stor` exists. `main.py` now creates the `data/` directory and the `metrics` table itself at startup, so restarting `shovly-web.service` (or re-running `uvicorn`) after upgrading should resolve it. If it persists, check `journalctl -u shovly-web.service -f` for the actual traceback and confirm `SHOVLY_DB_PATH` (if set) points to a writable location.

### `user_storage_cli.py: Permission denied`

This means the execute bit isn't set on the installed copy. `install.sh` runs `chmod +x` on it automatically; if you copied the file manually or are testing outside of the installer, fix it with:

```bash
sudo chmod +x /usr/local/bin/user_storage_cli.py
```

### `show_storage.sh` prints nothing when run manually

This is expected — the hook only runs its summary in an interactive login shell (`[[ $- == *i* ]]`), so invoking it directly with `sh /etc/profile.d/show_storage.sh` from an existing session is a no-op by design. To see the summary, start a new interactive SSH session (or run `bash -i /etc/profile.d/show_storage.sh`) after confirming `user_storage_cli.py` is executable and populated data exists for your username.