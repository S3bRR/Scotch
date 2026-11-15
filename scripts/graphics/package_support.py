#!/usr/bin/env python3
"""Package previously compiled, pinned graphics support; never downloads or publishes."""

import argparse, hashlib, json, re, shutil, subprocess, tarfile, tempfile
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument("--mesa-build", type=Path, required=True)
p.add_argument("--wine-build", type=Path, required=True)
p.add_argument("--mesa-source", type=Path, required=True)
p.add_argument("--moltenvk-archive", type=Path, required=True)
a = p.parse_args()
repo = Path(__file__).resolve().parents[2]
resources = repo / "Sources/ScotchRuntime/Resources"
version = json.loads((repo / "scripts/graphics/sources.json").read_text())["version"]
files = {
    "Graphics/libvulkan_kosmickrisp.dylib": a.mesa_build
    / "src/kosmickrisp/vulkan/libvulkan_kosmickrisp.dylib",
}
for folder, name in [
    ("win32u", "win32u"),
    ("winemac.drv", "winemac"),
    ("winevulkan", "winevulkan"),
    ("ntdll", "ntdll"),
]:
    files["MetalEngine/Engine/lib/wine/x86_64-unix/" + name + ".so"] = (
        a.wine_build / "dlls" / folder / (name + ".so")
    )
files["Wine/lib/wine/x86_64-unix/winevulkan.so"] = (
    a.wine_build / "dlls/winevulkan/winevulkan.so"
)
with tempfile.TemporaryDirectory(
    prefix="graphics-package-", dir=repo / ".build"
) as temp:
    root = Path(temp)
    lock = json.loads((repo / "scripts/graphics/sources.json").read_text())
    if (
        hashlib.sha256(a.moltenvk_archive.read_bytes()).hexdigest()
        != lock["moltenvk"]["sha256"]
    ):
        raise SystemExit("MoltenVK archive checksum mismatch")
    molten = root / "Graphics/libMoltenVK.dylib"
    molten.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(a.moltenvk_archive) as source:
        molten.write_bytes(
            source.extractfile(
                "MoltenVK/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib"
            ).read()
        )
    files["Graphics/libMoltenVK.dylib"] = molten
    router = root / "router.dylib"
    subprocess.run(
        [
            "/usr/bin/clang",
            "-arch",
            "x86_64",
            "-mmacosx-version-min=26.0",
            "-O2",
            "-fvisibility=hidden",
            "-dynamiclib",
            "-I",
            str(a.mesa_source / "include"),
            str(repo / "scripts/graphics/ScotchVulkanRouter.c"),
            "-install_name",
            "@rpath/libscotch_vulkan_router.dylib",
            "-o",
            str(router),
        ],
        check=True,
    )
    files["Graphics/libvulkan.1.dylib"] = router
    for member, source in files.items():
        target = root / member
        target.parent.mkdir(parents=True, exist_ok=True)
        if source.resolve() != target.resolve():
            shutil.copy2(source, target)
        arches = subprocess.check_output(
            ["/usr/bin/lipo", "-archs", str(target)], text=True
        ).split()
        if "x86_64" not in arches:
            raise SystemExit("Missing Wine/Rosetta architecture: " + member)
        info = subprocess.check_output(["/usr/bin/otool", "-l", str(target)], text=True)
        for path in re.findall(
            r"cmd LC_RPATH\s+cmdsize \d+\s+path (.*?) \(offset", info
        ):
            if not path.startswith("@"):
                subprocess.run(
                    ["/usr/bin/install_name_tool", "-delete_rpath", path, str(target)],
                    check=True,
                    capture_output=True,
                )
        if target.suffix == ".so":
            subprocess.run(
                [
                    "/usr/bin/install_name_tool",
                    "-add_rpath",
                    "@loader_path/../..",
                    str(target),
                ],
                check=True,
                capture_output=True,
            )
        deps = subprocess.check_output(["/usr/bin/otool", "-L", str(target)], text=True)
        for line in deps.splitlines()[1:]:
            if not line.startswith("\t"):
                continue
            dep = line.strip().split(" (compatibility")[0]
            if not dep.startswith(("@", "/usr/lib/", "/System/Library/")):
                raise SystemExit("Nonportable dependency: " + dep)
        build = subprocess.check_output(
            ["/usr/bin/xcrun", "vtool", "-show-build", str(target)], text=True
        )
        for minimum in re.findall(r"minos (\d+)\.", build):
            if int(minimum) > 26:
                raise SystemExit("Unexpected minimum macOS: " + build)
        subprocess.run(
            ["/usr/bin/strip", "-S", str(target)], check=True, capture_output=True
        )
        subprocess.run(
            [
                "/usr/bin/codesign",
                "--force",
                "--sign",
                "-",
                "--timestamp=none",
                str(target),
            ],
            check=True,
            capture_output=True,
        )
        subprocess.run(
            ["/usr/bin/codesign", "--verify", "--strict", str(target)],
            check=True,
            capture_output=True,
        )
    for member, target in [
        (
            "MetalEngine/Engine/lib/libvulkan.1.dylib",
            "../../../Graphics/libvulkan.1.dylib",
        ),
        ("Wine/lib/libvulkan.1.dylib", "../../Graphics/libvulkan.1.dylib"),
    ]:
        alias = root / member
        alias.parent.mkdir(parents=True, exist_ok=True)
        alias.symlink_to(target)
    (root / "Graphics/kosmickrisp_icd.json").write_text(
        json.dumps(
            {
                "file_format_version": "1.0.0",
                "ICD": {
                    "api_version": "1.4.0",
                    "library_path": "./libvulkan_kosmickrisp.dylib",
                },
            }
        )
        + "\n"
    )
    (root / "Graphics/moltenvk_icd.json").write_text(
        json.dumps(
            {
                "file_format_version": "1.0.0",
                "ICD": {
                    "api_version": "1.4.0",
                    "library_path": "./libMoltenVK.dylib",
                    "is_portability_driver": True,
                },
            }
        )
        + "\n"
    )
    router.unlink()
    shutil.copytree(repo / "ThirdParty/GraphicsSupport", root / "Graphics/Licenses")
    shutil.copy2(repo / "scripts/graphics/sources.json", root / "Graphics/Sources.json")
    (root / "Graphics/Version").write_text(version)
    hashes = {
        f.relative_to(root).as_posix(): hashlib.sha256(f.read_bytes()).hexdigest()
        for f in sorted(root.rglob("*"))
        if f.is_file()
    }
    archive = resources / "GraphicsSupport.tar.xz"
    with tarfile.open(archive, "w:xz", preset=6) as tar:
        for f in sorted(root.rglob("*")):
            if not f.is_file():
                continue
            info = tar.gettarinfo(f, arcname=f.relative_to(root).as_posix())
            info.uid = info.gid = info.mtime = 0
            info.uname = info.gname = ""
            info.mode = 0o755 if f.suffix in (".so", ".dylib") else 0o644
            with f.open("rb") as src:
                tar.addfile(info, src)
    sha = hashlib.sha256(archive.read_bytes()).hexdigest()
    entries = "\n".join(
        "        " + json.dumps(k) + ": " + json.dumps(v) + ","
        for k, v in hashes.items()
    )
    swift = """// Generated by scripts/graphics/package_support.py. Source pins and build recipe: scripts/graphics/.
import Foundation
import ScotchDomain
import ScotchInfrastructure

public enum GraphicsSupportInstallation {
    public static let version = "%s"
    static let archiveSHA256 = "%s"
    static let files: [String: String] = [
%s
    ]
    public static func verify(in libraries: URL) throws {
        for (member, hash) in files {
            let file = libraries.appending(path: member)
            guard file.resolvingSymlinksInPath().path.hasPrefix(libraries.resolvingSymlinksInPath().path + "/"),
                  (try? SHA256Checksum.hashFile(at: file)) == hash else {
                throw RuntimeInstallerError.installFailed("Graphics support needs repair: \\(member). Use Update.")
            }
        }
    }
}
""" % (
        version,
        sha,
        entries,
    )
    (
        repo / "Sources/ScotchRuntime/Runtime/GraphicsSupportInstallation.swift"
    ).write_text(swift)
    (repo / "scripts/graphics/artifacts.json").write_text(
        json.dumps(
            {"version": version, "archiveSHA256": sha, "files": hashes}, indent=2
        )
        + "\n"
    )
    print(str(archive), archive.stat().st_size, sha)
