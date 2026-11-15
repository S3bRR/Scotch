#!/usr/bin/env python3
"""Extract the pinned SDK's build libraries without running its installer."""

import argparse, hashlib, json, struct, subprocess, tempfile, zipfile, zlib
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument("archive", type=Path)
p.add_argument("output", type=Path)
a = p.parse_args()
repo = Path(__file__).resolve().parents[2]
lock = json.loads((repo / "scripts/graphics/sources.json").read_text())
if hashlib.sha256(a.archive.read_bytes()).hexdigest() != lock["vulkan_sdk"]["sha256"]:
    p.error("SDK checksum mismatch")
if a.output.exists():
    p.error("Output must be a new directory")
a.output.mkdir(parents=True)
with tempfile.TemporaryDirectory(prefix="sdk-extract-") as temp:
    temp = Path(temp)
    with zipfile.ZipFile(a.archive) as archive:
        name = next(x for x in archive.namelist() if x.endswith(".dat"))
        data = archive.read(name)
    pos = 0
    found = False
    while True:
        pos = data.find(b"7z\xbc\xaf\x27\x1c", pos)
        if pos < 0:
            break
        start = pos
        pos += 6
        if (
            start + 32 > len(data)
            or zlib.crc32(data[start + 12 : start + 32])
            != struct.unpack_from("<I", data, start + 8)[0]
        ):
            continue
        off, size = struct.unpack_from("<QQ", data, start + 12)
        end = start + 32 + off + size
        if end > len(data):
            continue
        part = temp / "payload.7z"
        part.write_bytes(data[start:end])
        pos = end
        listing = subprocess.check_output(["7z", "l", "-slt", str(part)], text=True)
        if "macOS/lib/libvulkan.1.4.363.dylib" not in listing:
            continue
        subprocess.run(
            [
                "7z",
                "x",
                "-y",
                str(part),
                "-o" + str(a.output.resolve()),
                "macOS/include/*",
                "macOS/lib/*",
                "macOS/share/vulkan/*",
            ],
            check=True,
        )
        found = True
        break
    if not found:
        raise SystemExit("SDK library payload was not found")
lib = a.output / "macOS/lib"
for alias, target in [
    ("libvulkan.1.dylib", "libvulkan.1.4.363.dylib"),
    ("libvulkan.dylib", "libvulkan.1.dylib"),
]:
    p = lib / alias
    if p.exists() or p.is_symlink():
        p.unlink()
    p.symlink_to(target)
print("Extracted build dependencies to", a.output / "macOS")
