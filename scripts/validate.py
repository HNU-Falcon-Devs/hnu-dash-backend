"""Validate the checked-in Supabase foundation without a hosted project."""

from pathlib import Path
import re
import tomllib

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "supabase" / "config.toml"
MIGRATIONS = ROOT / "supabase" / "migrations"

with CONFIG.open("rb") as file:
    config = tomllib.load(file)

assert config.get("project_id") == "hnu-dash-backend", "Unexpected local project ID"
assert config.get("db", {}).get("major_version") == 17, "Expected PostgreSQL 17"
assert config["db"]["migrations"]["enabled"] is True, "Migrations must stay enabled"
assert config["db"]["seed"]["enabled"] is False, "Seed data is deferred"
assert MIGRATIONS.is_dir(), "Migration directory is missing"

for path in MIGRATIONS.iterdir():
    if path.suffix == ".sql":
        assert re.fullmatch(r"\d{14}_[a-z0-9_]+\.sql", path.name), path.name

print("Supabase configuration and migration layout valid")
