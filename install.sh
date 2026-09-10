#!/bin/bash
# Exit immediately if any command fails
set -e

APP_DIR="/opt/shovly-stor"
BIN_DIR="/usr/local/bin"
PROFILE_DIR="/etc/profile.d"
WEB_SERVICE="/etc/systemd/system/shovly-web.service"
COLLECTOR_SERVICE="/etc/systemd/system/shovly-collector.service"

echo "[+] Starting Shovly-stor Enterprise installation..."

# 1. Verify root privileges
if [ "$EUID" -ne 0 ]; then
    echo "[-] Error: This installation script must be run with sudo or as root."
    exit 1
fi

# 2. Install system package dependencies
echo "[+] Installing system dependencies..."
apt-get update && apt-get install -y python3 python3-pip python3-venv sqlite3

# 3. Create application and data directory structure
echo "[+] Setting up application directory structure at ${APP_DIR}..."
mkdir -p "${APP_DIR}/templates"
mkdir -p "${APP_DIR}/data"

# 4. Copy core application files
echo "[+] Copying application files..."
if [ -f "main.py" ]; then
    cp main.py "${APP_DIR}/"
else
    echo "[-] Warning: main.py not found in current directory."
fi

if [ -f "collector.py" ]; then
    cp collector.py "${APP_DIR}/"
else
    echo "[-] Warning: collector.py not found in current directory."
fi

if [ -d "templates" ]; then
    cp -r templates/* "${APP_DIR}/templates/"
else
    echo "[-] Warning: templates/ directory not found."
fi

if [ -f "user_storage_cli.py" ]; then
    cp user_storage_cli.py "${BIN_DIR}/user_storage_cli.py"
    chmod +x "${BIN_DIR}/user_storage_cli.py"
else
    echo "[-] Warning: user_storage_cli.py not found."
fi

# 5. Set up secure environment variables file (.env)
if [ ! -f "${APP_DIR}/.env" ]; then
    echo "[+] Creating default production .env configuration file..."
    cat << 'EOF' > "${APP_DIR}/.env"
ONEFS_URL=https://isilon.local:8080
VARONIS_URL=https://varonis.local/api
METRICS_USER=readonly-metrics-user
METRICS_PASSWORD=YourSecureProductionPasswordHere
ADMIN_USER=admin
ADMIN_PASSWORD=SuperSecretAdminPassword
EOF
    chmod 600 "${APP_DIR}/.env"
    echo "[!] IMPORTANT: Update credentials in ${APP_DIR}/.env before relying on live API scraping!"
else
    echo "[+] Existing .env file found; preserving current credentials."
fi

# 6. Set up Python Virtual Environment and Dependencies
echo "[+] Installing Python requirements inside virtual environment..."
python3 -m venv "${APP_DIR}/venv"
"${APP_DIR}/venv/bin/pip" install --upgrade pip
if [ -f "requirements.txt" ]; then
    cp requirements.txt "${APP_DIR}/requirements.txt"
    "${APP_DIR}/venv/bin/pip" install -r "${APP_DIR}/requirements.txt"
else
    echo "[-] Warning: requirements.txt not found; installing default dependency set."
    "${APP_DIR}/venv/bin/pip" install fastapi uvicorn requests rich jinja2 python-dotenv
fi

# 7. Configure SSH Login Interactive Hook
echo "[+] Installing SSH login script hook..."
cat << 'EOF' > "${PROFILE_DIR}/show_storage.sh"
#!/bin/bash
# Executes the storage summary utility on interactive SSH login
if [[ $- == *i* ]]; then
    CLI_SCRIPT="/usr/local/bin/user_storage_cli.py"
    if [[ -x "$CLI_SCRIPT" ]]; then
        timeout 2s python3 "$CLI_SCRIPT" "$USER" 2>/dev/null
        echo ""
    fi
fi
EOF
chmod +x "${PROFILE_DIR}/show_storage.sh"

# 8. Register and Start FastAPI Web Dashboard Service
echo "[+] Registering FastAPI web dashboard systemd service..."
cat << EOF > "${WEB_SERVICE}"
[Unit]
Description=Shovly-stor Web Dashboard Service
After=network.target

[Service]
User=root
WorkingDirectory=${APP_DIR}
ExecStart=${APP_DIR}/venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 9. Register and Start Background Collector Daemon Service
echo "[+] Registering background collector daemon systemd service..."
cat << EOF > "${COLLECTOR_SERVICE}"
[Unit]
Description=Shovly-stor Background Collector Daemon
After=network.target

[Service]
User=root
WorkingDirectory=${APP_DIR}
ExecStart=${APP_DIR}/venv/bin/python collector.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 10. Reload systemd daemon and enable services
echo "[+] Enabling and starting systemd services..."
systemctl daemon-reload
systemctl enable --now shovly-web.service
systemctl enable --now shovly-collector.service

echo "[+] Shovly-stor installation complete successfully!"
echo "[*] Web dashboard available at: http://<server-ip>:8000"
echo "[*] Health check endpoint: http://<server-ip>:8000/healthz"