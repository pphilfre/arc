"""Package an unsigned device build, retaining framework symlinks and permissions."""
import argparse
import os
from pathlib import Path
import plistlib
import zipfile

def package(app, output):
    if not app.is_dir() or app.name != "Arc.app":
        raise ValueError("Expected a device build of Arc.app")
    with (app / "Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    if info.get("CFBundleIdentifier") != "dev.freddiephilpot.arc":
        raise ValueError("Unexpected application identifier")
    if info.get("DTPlatformName") != "iphoneos":
        raise ValueError("An IPA requires an iphoneos device build, not a simulator build")
    executable = app / info["CFBundleExecutable"]
    if not executable.is_file():
        raise ValueError("Application executable is missing")
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(app.rglob("*")):
            if path.is_dir() and not path.is_symlink():
                continue
            relative = Path("Payload") / app.name / path.relative_to(app)
            entry = zipfile.ZipInfo(relative.as_posix())
            entry.create_system = 3
            entry.external_attr = path.lstat().st_mode << 16
            entry.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(entry, os.readlink(path).encode() if path.is_symlink() else path.read_bytes())
    print(f"Packaged {output.name}: Payload/Arc.app")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("app", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    package(args.app, args.output)
