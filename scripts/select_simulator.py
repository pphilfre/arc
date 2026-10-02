"""Choose an available iPhone on iOS 26 for CI unit tests."""
import json
import subprocess
devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "--json"]))["devices"]
for runtime, entries in sorted(devices.items(), reverse=True):
    if ".iOS-26-" not in runtime:
        continue
    for device in entries:
        if device.get("isAvailable") and device["name"].startswith("iPhone"):
            print(device["udid"])
            raise SystemExit(0)
raise SystemExit("No available iOS 26 iPhone simulator on this runner")
