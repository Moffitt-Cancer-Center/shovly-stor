import os
import sys
import sqlite3
from rich.console import Console
from rich.table import Table

console = Console()

# Production installs run this from /usr/local/bin, so the DB path must be
# absolute; allow override via env var for local testing.
DB_PATH = os.getenv("SHOVLY_DB_PATH", "/opt/shovly-stor/data/Shovly-stor")


def fetch_user_metrics(username):
    if not os.path.exists(DB_PATH):
        return None
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        row = conn.execute(
            "SELECT usage_tb, limit_tb, stale_data_pct, iops, grace_period "
            "FROM metrics WHERE username = ?",
            (username,),
        ).fetchone()
    finally:
        conn.close()
    return dict(row) if row else None


def display_user_metrics(username):
    data = fetch_user_metrics(username)
    if data is None:
        console.print(f"[yellow]No storage metrics available yet for '{username}'.[/yellow]")
        return

    table = Table(title=f"Storage Summary for {username}")
    table.add_column("Metric", style="cyan")
    table.add_column("Value", style="magenta")

    table.add_row("Capacity Usage", f"{data['usage_tb']} TB / {data['limit_tb']} TB")
    table.add_row("Stale Data (>180d)", f"{data['stale_data_pct']}%")
    table.add_row("Current IOPS", f"{data['iops']}")
    table.add_row("Grace Period", f"{data['grace_period']}")

    console.print(table)

if __name__ == "__main__":
    if len(sys.argv) > 1:
        try:
            display_user_metrics(sys.argv[1])
        except Exception as e:
            console.print(f"[red]Failed to load storage metrics: {e}[/red]")