import os
import sqlite3
from fastapi import FastAPI, Depends, HTTPException, Request, status
from fastapi.security import HTTPBasic, HTTPBasicCredentials
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from dotenv import load_dotenv
import secrets

load_dotenv()
app = FastAPI(title="Shovly-stor Production Dashboard")
security = HTTPBasic()

templates = Jinja2Templates(directory="templates")
DB_PATH = os.getenv("SHOVLY_DB_PATH", "data/Shovly-stor")

def verify_admin(credentials: HTTPBasicCredentials = Depends(security)):
    correct_user = secrets.compare_digest(credentials.username, os.getenv("ADMIN_USER", "admin"))
    correct_pass = secrets.compare_digest(credentials.password, os.getenv("ADMIN_PASSWORD", "secret"))
    if not (correct_user and correct_pass):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Basic"},
        )
    return credentials.username

def get_db_connection():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

@app.get("/healthz", summary="Health Check")
def health_check():
    try:
        conn = get_db_connection()
        conn.execute("SELECT 1")
        conn.close()
        return {"status": "healthy", "database": "connected"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/users", summary="List all user metrics")
def get_all_users(admin: str = Depends(verify_admin)):
    conn = get_db_connection()
    users = conn.execute("SELECT username, usage_tb, limit_tb, stale_data_pct FROM metrics").fetchall()
    conn.close()
    return [dict(user) for user in users]

@app.get("/api/users/{username}/metrics", summary="Get detailed metrics for a specific user")
def get_user_metrics(username: str, admin: str = Depends(verify_admin)):
    conn = get_db_connection()
    user_data = conn.execute("SELECT * FROM metrics WHERE username = ?", (username,)).fetchone()
    conn.close()
    if not user_data:
        raise HTTPException(status_code=404, detail="User metrics not found")
    return dict(user_data)

@app.get("/", response_class=HTMLResponse, summary="Load the web dashboard")
def dashboard_home(request: Request, admin: str = Depends(verify_admin)):
    return templates.TemplateResponse(request, "dashboard.html")