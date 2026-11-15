#!/usr/bin/env python3
"""Discover candidates only. No feed promotion, signing, upload, or PR mutation."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import tempfile
import subprocess
import urllib.request

SOURCES = {
    "wine": ("Gcenx/macOS_Wine_builds", ["wine-staging-", "-osx64"]),
    "dxvk": ("Gcenx/DXVK-macOS", ["dxvk-macOS-async", "-repack.tar"]),
    "dxmt": ("3Shain/dxmt", ["dxmt-", "builtin.tar"]),
    "zink": ("pal1000/mesa-dist-win", ["mesa3d-", "-release-msvc.7z"]),
}


def request(url):
    headers = {
        "User-Agent": "Scotch-runtime-discovery",
        "Accept": "application/vnd.github+json",
    }
    if os.environ.get("GH_TOKEN") and url.startswith("https://api.github.com/"):
        headers["Authorization"] = "Bearer " + os.environ["GH_TOKEN"]
    return urllib.request.urlopen(
        urllib.request.Request(url, headers=headers), timeout=60
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--download",
        action="store_true",
        help="Download candidates and validate size/digest. Layout and GPU approval still required.",
    )
    args = parser.parse_args()
    report = {
        "status": "candidates-only",
        "requiresMaintainerApproval": True,
        "components": {},
        "d3dmetal": {
            "source": "Gcenx/game-porting-toolkit",
            "requiresMatchedLoader": True,
        },
    }
    for component, (repo, patterns) in SOURCES.items():
        releases = json.load(
            request(f"https://api.github.com/repos/{repo}/releases?per_page=50")
        )
        matches = [
            (r, a)
            for r in releases
            if not r.get("draft") and not r.get("prerelease")
            for a in r["assets"]
            if all(p in a["name"] for p in patterns)
        ]
        if not matches:
            report["components"][component] = {
                "error": "No supported archive candidate found"
            }
            continue
        release, asset = matches[0]
        item = {
            "component": component,
            "repo": repo,
            "version": release["tag_name"],
            "url": asset["browser_download_url"],
            "fileName": asset["name"],
            "size": asset["size"],
            "published": release["published_at"],
            "upstreamDigest": asset.get("digest"),
            "layoutValidated": False,
            "gameCompatibilityValidated": False,
        }
        if args.download:
            digest = hashlib.sha256()
            size = 0
            with tempfile.TemporaryDirectory(prefix="ScotchCandidate-") as temp:
                path = Path(temp) / "archive"
                with request(item["url"]) as stream, path.open("wb") as archive:
                    while chunk := stream.read(1024 * 1024):
                        archive.write(chunk)
                        digest.update(chunk)
                        size += len(chunk)
                listing = subprocess.check_output(
                    ["/usr/bin/tar", "-tf", str(path)], text=True
                ).splitlines()
                assert all(
                    not x.startswith("/") and ".." not in x.split("/") for x in listing
                ), "Unsafe archive paths"
                expected = {
                    "wine": [
                        "bin/wine",
                        "bin/wineserver",
                        "x86_64-unix/winemac.so",
                        "libMoltenVK.dylib",
                    ],
                    "dxvk": ["x64/d3d11.dll", "x32/d3d11.dll"],
                    "dxmt": ["x86_64-windows/d3d11.dll", "i386-windows/d3d11.dll"],
                    "zink": [
                        "x64/" + x
                        for x in [
                            "opengl32.dll",
                            "libgallium_wgl.dll",
                            "libEGL.dll",
                            "libGLESv1_CM.dll",
                            "libGLESv2.dll",
                        ]
                    ]
                    + [
                        "x86/" + x
                        for x in [
                            "opengl32.dll",
                            "libgallium_wgl.dll",
                            "libEGL.dll",
                            "libGLESv1_CM.dll",
                            "libGLESv2.dll",
                        ]
                    ],
                }[component]
                item["missingLayoutEntries"] = [
                    name
                    for name in expected
                    if not any(x.endswith(name) for x in listing)
                ]
                item["layoutValidated"] = not item["missingLayoutEntries"]
            if size != item["size"]:
                raise RuntimeError(f"{component}: size mismatch")
            item["sha256"] = digest.hexdigest()
            if (
                item["upstreamDigest"]
                and item["upstreamDigest"] != "sha256:" + item["sha256"]
            ):
                raise RuntimeError(f"{component}: upstream digest mismatch")
        report["components"][component] = item
    # Native driver/loader compatibility is client-coupled. New upstream tags
    # remain candidates until the complete profile passes hardware validation.
    molten = json.load(
        request("https://api.github.com/repos/KhronosGroup/MoltenVK/releases/latest")
    )
    report["moltenvk"] = {
        "version": molten["tag_name"],
        "informationalOnly": True,
        "distribution": "pinned in the client native graphics profile",
    }
    graphics = Path(__file__).resolve().parents[1] / "graphics"
    report["nativeProfile"] = {
        "sources": json.loads((graphics / "sources.json").read_text()),
        "artifacts": json.loads((graphics / "artifacts.json").read_text()),
        "requiresClientReleaseForChanges": True,
        "hardwareCompatibilityValidated": False,
    }
    # D3DMetal is an ABI pair, not an arbitrary framework overlay. Report
    # upstream payload/loader candidates without silently promoting either.
    for label, repo, tag, name in [
        (
            "payload",
            "Gcenx/game-porting-toolkit",
            "Game-Porting-Toolkit-3.0-3",
            "game-porting-toolkit-3.0-3.tar.xz",
        ),
        ("matchedEngine", "Alien4042x/WineForge", "0.6.0.3", "WineForge.dmg"),
    ]:
        release = json.load(
            request(f"https://api.github.com/repos/{repo}/releases/tags/{tag}")
        )
        asset = next(a for a in release["assets"] if a["name"] == name)
        report["d3dmetal"][label] = {
            "repo": repo,
            "version": tag,
            "url": asset["browser_download_url"],
            "size": asset["size"],
            "digest": asset.get("digest"),
            "gameCompatibilityValidated": False,
        }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(f"Saved {args.output}. Candidates are not approved updates.")


if __name__ == "__main__":
    main()
