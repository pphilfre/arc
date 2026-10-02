"""Generate runtime configuration without placing the downloads secret in the app."""
import argparse
import os
from pathlib import Path
import plistlib
import re

ROOT = Path(__file__).resolve().parents[1]
BUNDLE_ID = "dev.freddiephilpot.arc"

def read_env(path):
    values = {}
    if not path.exists():
        return values
    for number, raw in enumerate(path.read_text(encoding="utf-8-sig").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[7:]
        if "=" not in line:
            raise ValueError(f"Invalid environment assignment at line {number}")
        key, value = line.split("=", 1)
        if not re.fullmatch(r"[A-Z][A-Z0-9_]*", key.strip()):
            raise ValueError(f"Invalid environment key at line {number}")
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        values[key.strip()] = value
    return values

def configure(env_file, output):
    values = read_env(env_file)
    # CI environment always takes precedence over a local file.
    for key in ("MAPBOX_ACCESS_TOKEN", "ARC_BUNDLE_IDENTIFIER", "ARC_BUILD_ENVIRONMENT", "ARC_HIDE_MAP_ATTRIBUTION"):
        if key in os.environ:
            values[key] = os.environ[key]
    if values.get("ARC_BUNDLE_IDENTIFIER", BUNDLE_ID) != BUNDLE_ID:
        raise ValueError(f"Arc's bundle identifier must be {BUNDLE_ID}")
    token = values.get("MAPBOX_ACCESS_TOKEN", "")
    if not token.startswith("pk.") or "replace_with" in token or any(c.isspace() for c in token):
        raise ValueError("Set MAPBOX_ACCESS_TOKEN to a valid public pk. token")
    with (ROOT / "Config/Arc-Info.template.plist").open("rb") as stream:
        info = plistlib.load(stream)
    info["MBXAccessToken"] = token
    environment = values.get("ARC_BUILD_ENVIRONMENT", "production")
    if environment not in ("development", "production"):
        raise ValueError("ARC_BUILD_ENVIRONMENT must be development or production")
    info["ArcDevelopmentMode"] = environment == "development"
    info["ArcHideMapAttribution"] = environment == "development" and values.get("ARC_HIDE_MAP_ATTRIBUTION", "false").lower() == "true"
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("wb") as stream:
        plistlib.dump(info, stream, sort_keys=False)
    print("Generated Arc configuration (credentials redacted).")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--env", type=Path, default=ROOT / ".env.local")
    parser.add_argument("--output", type=Path, default=ROOT / "Config/Generated/Arc-Info.plist")
    args = parser.parse_args()
    try:
        configure(args.env, args.output)
    except ValueError as error:
        parser.exit(1, f"Configuration error: {error}\n")

