#!/usr/bin/env python3
import os
import plistlib
import subprocess
import tempfile
from pathlib import Path
from urllib.parse import urlparse


def status(name: str, result: str, details: str):
    return {"name": name, "result": result, "details": details}


def read_plist(path: Path):
    with path.open("rb") as f:
        return plistlib.load(f)


def parse_path(raw):
    if isinstance(raw, bytes):
        raw = raw.decode("utf-8", errors="ignore")
    if not isinstance(raw, str):
        return None
    if raw.startswith("file://"):
        return urlparse(raw).path
    return raw


def run_command(cmd, env=None, timeout=30):
    try:
        proc = subprocess.run(
            cmd,
            env=env,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
        return proc.returncode, proc.stdout.strip(), proc.stderr.strip()
    except subprocess.TimeoutExpired:
        return 124, "", "timeout"


def main():
    home = Path.home()
    bundle_id = "com.s3brr.Scotch"

    container_dir = home / "Library" / "Containers" / bundle_id
    app_support_dir = home / "Library" / "Application Support" / bundle_id
    logs_dir = home / "Library" / "Logs" / bundle_id

    runtime_bin = app_support_dir / "Libraries" / "Wine" / "bin" / "wine"
    runtime_server = app_support_dir / "Libraries" / "Wine" / "bin" / "wineserver"
    runtime_bundle = app_support_dir / "Libraries" / "Wine.app"
    runtime_manifest = app_support_dir / "Libraries" / "ScotchRuntimeManifest.plist"
    gpu_spoof_shim = app_support_dir / "Libraries" / "VulkanSpoof" / "libscotch_gpu_spoof.dylib"
    winetricks = app_support_dir / "Libraries" / "winetricks"

    new_catalog = container_dir / "BottleCatalog.plist"
    old_catalog = container_dir / "BottleVM.plist"

    checks = []

    rosetta = Path("/Library/Apple/usr/libexec/oah/libRosettaRuntime")
    checks.append(status(
        "Rosetta availability",
        "PASS" if rosetta.exists() else "FAIL",
        str(rosetta),
    ))

    runtime_ready = runtime_bin.exists() and runtime_server.exists() and runtime_bundle.exists()
    checks.append(status(
        "Runtime binaries",
        "PASS" if runtime_ready else "FAIL",
        f"wine={runtime_bin.exists()} wineserver={runtime_server.exists()} bundle={runtime_bundle.exists()}",
    ))

    checks.append(status(
        "Runtime manifest",
        "PASS" if runtime_manifest.exists() else "SKIP",
        str(runtime_manifest),
    ))

    checks.append(status(
        "GPU spoof shim",
        "PASS" if gpu_spoof_shim.exists() else "SKIP",
        str(gpu_spoof_shim),
    ))

    checks.append(status(
        "Winetricks install",
        "PASS" if winetricks.exists() else "SKIP",
        str(winetricks),
    ))

    catalog_source = None
    raw_paths = []
    if new_catalog.exists():
        data = read_plist(new_catalog)
        raw_paths = data.get("bottlePaths", [])
        catalog_source = new_catalog
        if not raw_paths and old_catalog.exists():
            data = read_plist(old_catalog)
            raw_paths = data.get("paths", [])
            catalog_source = old_catalog
    elif old_catalog.exists():
        data = read_plist(old_catalog)
        raw_paths = data.get("paths", [])
        catalog_source = old_catalog

    bottle_paths = []
    for raw in raw_paths:
        parsed = parse_path(raw)
        if parsed:
            bottle_paths.append(Path(parsed))

    checks.append(status(
        "Bottle discovery",
        "PASS" if bottle_paths else "FAIL",
        f"source={catalog_source} count={len(bottle_paths)}",
    ))

    metadata_ok = 0
    metadata_fail = 0
    for bottle in bottle_paths:
        metadata = bottle / "Metadata.plist"
        if not metadata.exists():
            metadata_fail += 1
            continue
        try:
            read_plist(metadata)
            metadata_ok += 1
        except Exception:
            metadata_fail += 1

    checks.append(status(
        "Bottle metadata decode",
        "PASS" if metadata_fail == 0 and metadata_ok > 0 else ("FAIL" if metadata_fail > 0 else "SKIP"),
        f"ok={metadata_ok} fail={metadata_fail}",
    ))

    first_bottle = bottle_paths[0] if bottle_paths else None
    program_settings_dir = first_bottle / "Program Settings" if first_bottle else None
    checks.append(status(
        "Program settings folder",
        "PASS" if program_settings_dir and program_settings_dir.exists() else "SKIP",
        str(program_settings_dir) if program_settings_dir else "no bottle discovered",
    ))

    if not logs_dir.exists():
        logs_dir.mkdir(parents=True, exist_ok=True)
    try:
        temp_log = logs_dir / "validation-write-test.log"
        temp_log.write_text("validation\n", encoding="utf-8")
        temp_log.unlink(missing_ok=True)
        checks.append(status("Log path writable", "PASS", str(logs_dir)))
    except Exception as exc:
        checks.append(status("Log path writable", "FAIL", str(exc)))

    has_steam = False
    for bottle in bottle_paths:
        if (bottle / "drive_c" / "Program Files (x86)" / "Steam" / "steam.exe").exists() or (bottle / "drive_c" / "Program Files" / "Steam" / "steam.exe").exists():
            has_steam = True
            break

    checks.append(status(
        "Steam flow readiness",
        "PASS" if has_steam else "SKIP",
        "steam.exe detected" if has_steam else "steam.exe not found in discovered bottles",
    ))

    path_with_spaces = any(" " in str(path) for path in bottle_paths)
    checks.append(status(
        "Path handling with spaces",
        "PASS" if path_with_spaces else "SKIP",
        "At least one bottle path contains spaces" if path_with_spaces else "No bottle path with spaces was found",
    ))

    if runtime_ready and first_bottle:
        env = os.environ.copy()
        env["WINEPREFIX"] = str(first_bottle)
        env["WINEDEBUG"] = "fixme-all"
        env["PATH"] = f"{runtime_bin.parent}:{env.get('PATH', '')}"

        rc, out, err = run_command([str(runtime_bin), "cmd", "/c", "echo", "SCOTCH_V2_EXE_VALIDATION"], env=env, timeout=45)
        checks.append(status(
            "EXE launch smoke test",
            "PASS" if rc == 0 and "SCOTCH_V2_EXE_VALIDATION" in out else "FAIL",
            f"rc={rc} out={out[:120]} err={err[:120]}",
        ))

        rc, out, err = run_command([str(runtime_bin), "msiexec", "/?"], env=env, timeout=45)
        retried = False
        if rc == 124:
            retried = True
            rc, out, err = run_command([str(runtime_bin), "msiexec", "/?"], env=env, timeout=45)
        msi_ok = rc in (0, 1)
        checks.append(status(
            "MSI flow smoke test",
            "PASS" if msi_ok else "FAIL",
            f"rc={rc} retry={retried} out={out[:120]} err={err[:120]}",
        ))

        rc, out, err = run_command([str(runtime_bin), "tasklist.exe", "/FO", "CSV", "/NH"], env=env, timeout=45)
        checks.append(status(
            "Process listing smoke test",
            "PASS" if rc == 0 else "FAIL",
            f"rc={rc} out={out[:120]} err={err[:120]}",
        ))

        run_command([str(runtime_server), "-k"], env=env, timeout=15)
    else:
        checks.append(status("EXE launch smoke test", "SKIP", "Runtime or bottle missing"))
        checks.append(status("MSI flow smoke test", "SKIP", "Runtime or bottle missing"))
        checks.append(status("Process listing smoke test", "SKIP", "Runtime or bottle missing"))

    report_path = Path(__file__).resolve().parents[1] / "Docs" / "manual_validation_report.md"
    report_path.parent.mkdir(parents=True, exist_ok=True)

    pass_count = sum(1 for item in checks if item["result"] == "PASS")
    fail_count = sum(1 for item in checks if item["result"] == "FAIL")
    skip_count = sum(1 for item in checks if item["result"] == "SKIP")

    lines = []
    lines.append("# Manual Validation Report")
    lines.append("")
    lines.append("## Scope")
    lines.append("Validation against discovered real bottle data under the active user profile.")
    lines.append("")
    lines.append("## Summary")
    lines.append(f"- PASS: {pass_count}")
    lines.append(f"- FAIL: {fail_count}")
    lines.append(f"- SKIP: {skip_count}")
    lines.append("")
    lines.append("## Results")
    lines.append("")
    lines.append("| Check | Result | Details |")
    lines.append("|---|---|---|")

    for item in checks:
        details = item["details"].replace("|", "\\|").replace("\n", " ")
        lines.append(f"| {item['name']} | {item['result']} | {details} |")

    lines.append("")
    lines.append("## Paths")
    lines.append(f"- Container: `{container_dir}`")
    lines.append(f"- App Support: `{app_support_dir}`")
    lines.append(f"- Logs: `{logs_dir}`")

    report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(f"Wrote report: {report_path}")
    print(f"PASS={pass_count} FAIL={fail_count} SKIP={skip_count}")


if __name__ == "__main__":
    main()
