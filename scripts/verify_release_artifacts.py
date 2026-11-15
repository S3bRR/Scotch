#!/usr/bin/env python3
"""Audit the finished DMG and separately distributed corresponding sources."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tarfile
import tempfile


def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while block := source.read(1024 * 1024):
            digest.update(block)
    return digest.hexdigest()


def verify_checksum(directory, name):
    fields = (directory / (name + ".sha256")).read_text().split()
    assert len(fields) == 2 and fields[1] == name, "Unexpected checksum filename"
    digest = sha(directory / name)
    assert digest == fields[0], "Checksum mismatch: " + name
    return digest


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("directory", type=Path)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
directory = args.directory.resolve()
image = directory / "Scotch.dmg"
source = directory / "ScotchGraphicsSources.tar.xz"
dmg_sha = verify_checksum(directory, image.name)
source_sha = verify_checksum(directory, source.name)
expected = set(subprocess.check_output(["git", "ls-files", "-z", "-c", "-o", "--exclude-standard"], cwd=repo).decode().split("\0")) - {""}
expected = {name for name in expected if (repo / name).is_file() or (repo / name).is_symlink()}
seen = set()
with tarfile.open(source, "r|xz") as archive:
    for member in archive:
        if not member.name.startswith("Scotch/"):
            continue
        relative = member.name[len("Scotch/"):]
        if member.issym():
            assert relative in expected and member.linkname == os.readlink(repo / relative), relative
        elif member.isfile():
            assert relative in expected, relative
            assert hashlib.sha256(archive.extractfile(member).read()).hexdigest() == sha(repo / relative), relative
        else:
            continue
        seen.add(relative)
assert expected == seen, "Corresponding source differs: " + str(sorted(expected ^ seen))
subprocess.run(["hdiutil", "verify", str(image)], check=True, capture_output=True)
with tempfile.TemporaryDirectory(prefix="ScotchReleaseAudit-") as temporary:
    mount = Path(temporary) / "mount"
    mount.mkdir()
    subprocess.run(["hdiutil", "attach", "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", str(mount), str(image)], check=True, capture_output=True)
    try:
        assert {p.name for p in mount.iterdir() if not p.name.startswith(".")} == {"Scotch.app", "Applications"}, "Unexpected visible item in installer"
        assert (mount / "Applications").is_symlink() and os.readlink(mount / "Applications") == "/Applications"
        app = mount / "Scotch.app"
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        expected_info = plistlib.loads((repo / "Sources/ScotchApp/Info.plist").read_bytes())
        for key in ["CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion"]:
            assert info[key] == expected_info[key], key
        resources = app / "Contents/Resources/Scotch_ScotchRuntime.bundle"
        artifacts = json.loads((repo / "scripts/graphics/artifacts.json").read_text())
        assert sha(resources / "GraphicsSupport.tar.xz") == artifacts["archiveSHA256"]
        assert (resources / "SourceAvailability.txt").read_bytes() == (repo / "Sources/ScotchRuntime/Resources/SourceAvailability.txt").read_bytes()
        with (directory / "BundleValidation.log").open("w") as log:
            subprocess.run(["bash", str(repo / "scripts/verify_release_bundle.sh"), str(app)], check=True, cwd=repo, stdout=log, stderr=subprocess.STDOUT)
        usage = subprocess.check_output([str(app / "Contents/MacOS/ScotchCmd"), "--help"], text=True)
        assert "ScotchCmd usage:" in usage
    finally:
        subprocess.run(["hdiutil", "detach", str(mount)], check=True, capture_output=True)
receipt = {
    "commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip(),
    "version": info["CFBundleShortVersionString"],
    "build": info["CFBundleVersion"],
    "dmgSHA256": dmg_sha,
    "sourceSHA256": source_sha,
    "sourceFileCount": len(seen),
    "visibleItems": ["Applications", "Scotch.app"],
}
(directory / "ArtifactValidation.json").write_text(json.dumps(receipt, indent=2) + "\n")
print("Passed: DMG contains only Scotch.app and Applications; checksums, signatures, resources, CLI, native support and source availability verified.")
print("Passed: separate corresponding source matches all", len(seen), "release files.")
