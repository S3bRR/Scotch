#!/usr/bin/env python3
"""Exercise a real signed app replacement/relaunch on loopback, using unique test data."""

import functools
import argparse
import http.server
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import tempfile
import threading
import time
import uuid

REPO = Path(__file__).resolve().parents[1]
BUILD = REPO / ".build/release"
TOOLS = REPO / ".build/updater-tools/bin"


def run(*args, **kwargs):
    return subprocess.run([str(x) for x in args], check=True, **kwargs)


def sign(app):
    entitlement = REPO / "Sources/ScotchApp/Scotch.entitlements"
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    run(
        "codesign",
        "--force",
        "--sign",
        "-",
        "--options",
        "runtime",
        "--entitlements",
        entitlement,
        app / "Contents/MacOS" / info["CFBundleExecutable"],
    )
    run(
        "codesign",
        "--force",
        "--sign",
        "-",
        "--options",
        "runtime",
        "--entitlements",
        entitlement,
        app,
    )
    run("codesign", "--verify", "--deep", "--strict", app)


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_):
        pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=REPO / ".release/Scotch.app")
    source_app = parser.parse_args().app.resolve()
    assert (
        source_app / "Contents/Frameworks/Sparkle.framework"
    ).is_dir(), "Build the release package first"
    identity = "com.s3brr.Scotch.UpdaterProbe." + uuid.uuid4().hex
    data_root = Path.home() / "Library/Application Support" / identity
    cache = Path.home() / "Library/Caches" / identity
    preferences = Path.home() / "Library/Preferences" / (identity + ".plist")
    process = None
    with tempfile.TemporaryDirectory(prefix="ScotchAppUpdateProbe-") as temp:
        root = Path(temp)
        downloads = root / "downloads"
        downloads.mkdir()
        server = http.server.ThreadingHTTPServer(
            ("127.0.0.1", 0), functools.partial(QuietHandler, directory=downloads)
        )
        threading.Thread(target=server.serve_forever, daemon=True).start()
        origin = f"http://127.0.0.1:{server.server_port}/"
        marker = root / "relaunched"
        try:
            # Compile the real coordinator and delegate against the same release objects.
            objects = [
                str(p)
                for target in [
                    "ScotchDomain",
                    "ScotchInfrastructure",
                    "ScotchRuntime",
                    "ScotchFeatures",
                    "ScotchPE",
                ]
                for p in (BUILD / (target + ".build")).glob("*.o")
            ]
            probe = root / "UpdaterProbe"
            run(
                "swiftc",
                "-swift-version",
                "6",
                "-parse-as-library",
                "-I",
                BUILD / "Modules",
                "-F",
                BUILD,
                "-framework",
                "Sparkle",
                "-Xlinker",
                "-rpath",
                "-Xlinker",
                "@executable_path/../Frameworks",
                REPO / "scripts/AppUpdaterProbe.swift",
                REPO / "Sources/ScotchApp/ScotchAppUpdater.swift",
                REPO / "Sources/ScotchApp/ScotchAppDelegate.swift",
                *objects,
                "-o",
                probe,
            )
            app = root / "installed/ScotchUpdaterProbe.app"
            app.parent.mkdir()
            run("ditto", source_app, app)
            info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
            info.update(
                CFBundleIdentifier=identity,
                CFBundleName="ScotchUpdaterProbe",
                CFBundleDisplayName="ScotchUpdaterProbe",
                CFBundleExecutable="UpdaterProbe",
                CFBundleVersion="1",
                CFBundleShortVersionString="1.0.0",
                SUFeedURL=origin + "appcast.xml",
                SUEnableAutomaticChecks=False,
                NSAppTransportSecurity={"NSAllowsArbitraryLoads": True},
            )
            info["ScotchProbeMarker"] = str(marker)
            info["ScotchProbeRuntimeFeed"] = origin + "runtime.json"
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
            (app / "Contents/MacOS/ScotchApp").unlink()
            shutil.copy2(probe, app / "Contents/MacOS/UpdaterProbe")
            sign(app)
            new = root / "next/ScotchUpdaterProbe.app"
            new.parent.mkdir()
            run("ditto", app, new)
            new_info = dict(
                info, CFBundleVersion="2", CFBundleShortVersionString="2.0.0"
            )
            (new / "Contents/Info.plist").write_bytes(plistlib.dumps(new_info))
            # The same updater-enabled executable is used in the next build;
            # the Info.plist build number changes and a second check must be current.
            sign(new)
            archive = downloads / "ScotchUpdaterProbe.zip"
            run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", new, archive)
            run(
                TOOLS / "generate_appcast",
                "--download-url-prefix",
                origin,
                "--embed-release-notes",
                downloads,
            )
            run(TOOLS / "sign_update", "--verify", downloads / "appcast.xml")
            shutil.copy2(REPO / "updates/runtime.json", downloads / "runtime.json")
            save = data_root / "Bottles/game/drive_c/Save.dat"
            save.parent.mkdir(parents=True)
            save.write_bytes(b"preserved game save")
            catalog = data_root / "BottleVM.plist"
            catalog.write_bytes(
                plistlib.dumps(
                    {
                        "fileVersion": {"major": 1, "minor": 0, "patch": 0},
                        "bottlePaths": [
                            str(save.parent.parent),
                            "/Volumes/OfflineGames/ExternalPrefix",
                        ],
                    }
                )
            )
            original_catalog = catalog.read_bytes()
            env = dict(
                os.environ,
                SCOTCH_PROBE_MARKER=str(marker),
                SCOTCH_PROBE_RUNTIME_FEED=origin + "runtime.json",
                SCOTCH_UPDATE_TEST_FEED_URL=origin + "appcast.xml",
            )
            with (root / "probe.log").open("w") as log:
                launch = ["open", "-n", "-W", "-a", str(app)]
                for key in [
                    "SCOTCH_PROBE_MARKER",
                    "SCOTCH_PROBE_RUNTIME_FEED",
                    "SCOTCH_UPDATE_TEST_FEED_URL",
                ]:
                    launch += ["--env", key + "=" + env[key]]
                process = subprocess.Popen(launch, env=env, stdout=log, stderr=log)
                deadline = time.monotonic() + 90
                while time.monotonic() < deadline and not marker.exists():
                    time.sleep(0.5)
                if not marker.exists():
                    status = marker.with_suffix(".status")
                    raise RuntimeError(
                        (status.read_text() if status.exists() else "No updater status")
                        + "\n"
                        + (root / "probe.log").read_text()
                    )
            assert (
                plistlib.loads((app / "Contents/Info.plist").read_bytes())[
                    "CFBundleVersion"
                ]
                == "2"
            ), "App was not replaced"
            assert save.read_bytes() == b"preserved game save", "Save changed"
            assert (
                catalog.read_bytes() == original_catalog
            ), "Custom/external catalog changed"
            run("codesign", "--verify", "--deep", "--strict", app)
            print(
                "Passed: one Update action checked both feeds, authenticated the archive, replaced the app, relaunched, and preserved saves/catalog."
            )
        finally:
            server.shutdown()
            if process and process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
            # Stop only processes from this uniquely named, self-created fixture.
            if "app" in locals():
                matching = subprocess.run(
                    ["pgrep", "-f", str(app / "Contents/MacOS/UpdaterProbe")],
                    capture_output=True,
                    text=True,
                )
                for raw in matching.stdout.split():
                    try:
                        os.kill(int(raw), signal.SIGTERM)
                    except ProcessLookupError:
                        pass
                time.sleep(0.1)
            shutil.rmtree(data_root, ignore_errors=True)
            shutil.rmtree(cache, ignore_errors=True)
            preferences.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
