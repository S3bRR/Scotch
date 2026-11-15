#!/usr/bin/env python3
"""Build Scotch's private x86_64 graphics support from the pinned source archives.

Requires the compiler tools listed in sources.json, an extracted Vulkan SDK, and
FreeType headers. It writes only under --work and the generated support resources.
No system installation, upstream submission, or publication is performed.
"""

import argparse, hashlib, json, os, shutil, subprocess, tarfile
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument("--moltenvk-archive", type=Path, required=True)
p.add_argument("--mesa-archive", type=Path, required=True)
p.add_argument("--wine-archive", type=Path, required=True)
p.add_argument("--sdk", type=Path, required=True)
p.add_argument(
    "--engine",
    type=Path,
    required=True,
    help="Unmodified WineForgeCore tree (FreeType runtime)",
)
p.add_argument("--bison", type=Path, help="Bison 3.x executable")
p.add_argument("--freetype-include", type=Path, required=True)
p.add_argument("--env-json", type=Path, help="Optional private toolchain environment")
p.add_argument("--work", type=Path, default=Path(".build/graphics-rebuild"))
p.add_argument("--jobs", type=int, default=10)
p.add_argument("--no-package", action="store_true")
a = p.parse_args()
repo = Path(__file__).resolve().parents[2]
lock = json.loads((repo / "scripts/graphics/sources.json").read_text())
a.work = a.work.resolve()
a.sdk = a.sdk.resolve()
a.engine = a.engine.resolve()
a.freetype_include = a.freetype_include.resolve()
if a.work.exists():
    p.error("--work must be a new directory; existing build results are preserved")
env = os.environ.copy()
if a.env_json:
    env.update(json.loads(a.env_json.read_text()))
for name in ["CC", "CXX", "OBJC", "OBJCXX"]:
    env[name] = "/usr/bin/clang++" if name in ["CXX", "OBJCXX"] else "/usr/bin/clang"


def run(cmd, **kw):
    print(" ".join(map(str, cmd)), flush=True)
    subprocess.run(list(map(str, cmd)), env=kw.pop("env", env), check=True, **kw)


def source(archive, key):
    if hashlib.sha256(archive.read_bytes()).hexdigest() != lock[key]["sha256"]:
        raise SystemExit("Source checksum mismatch: " + str(archive))
    dest = a.work / key
    dest.mkdir(parents=True)
    with tarfile.open(archive) as t:
        # Python's data filter rejects unsafe paths and escaping archive links.
        t.extractall(dest, filter="data")
    return next(x for x in dest.iterdir() if x.is_dir())


mesa = source(a.mesa_archive, "mesa")
wine = source(a.wine_archive, "wine")
for root, patch in [
    (mesa, "kosmickrisp-zink.patch"),
    (wine, "wine-wow64-properties.patch"),
    (wine, "wine-steam-surfaces.patch"),
]:
    run(["/usr/bin/patch", "-p1", "-i", repo / "scripts/graphics" / patch], cwd=root)
# Only KosmicKrisp is patched; no changes to Mesa's protected driver directories.
pcs = a.work / "pkgconfig"
pcs.mkdir()
spv = a.sdk / "lib/pkgconfig"
env["PKG_CONFIG_PATH"] = str(spv) + ":" + env.get("PKG_CONFIG_PATH", "")
env["CMAKE_PREFIX_PATH"] = str(a.sdk) + ":" + env.get("CMAKE_PREFIX_PATH", "")
native = a.work / "mesa-native"
common = [
    "--buildtype=release",
    "-Dplatforms=macos",
    "-Dvulkan-drivers=kosmickrisp",
    "-Dgallium-drivers=",
    "-Dopengl=false",
    "-Dzstd=disabled",
    "--prefer-static",
]
run(
    [
        "meson",
        "setup",
        native,
        mesa,
        *common,
        "-Dllvm=enabled",
        "-Dmesa-clc=enabled",
        "-Dinstall-mesa-clc=true",
    ]
)
run(
    [
        "ninja",
        "-C",
        native,
        "src/compiler/clc/mesa_clc",
        "src/compiler/spirv/vtn_bindgen2",
        "-j" + str(a.jobs),
    ]
)
env["PATH"] = (
    str(native / "src/compiler/clc")
    + ":"
    + str(native / "src/compiler/spirv")
    + ":"
    + env["PATH"]
)
cross = a.work / "x86_64.ini"
cross.write_text("""[binaries]
c = ['/usr/bin/clang', '-arch', 'x86_64']
cpp = ['/usr/bin/clang++', '-arch', 'x86_64']
objc = ['/usr/bin/clang', '-arch', 'x86_64']
objcpp = ['/usr/bin/clang++', '-arch', 'x86_64']
ar = '/usr/bin/ar'
strip = '/usr/bin/strip'
pkg-config = '%s'
[host_machine]
system = 'darwin'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
[properties]
needs_exe_wrapper = false
[built-in options]
c_args = ['-mmacosx-version-min=26.0']
cpp_args = ['-mmacosx-version-min=26.0']
objc_args = ['-mmacosx-version-min=26.0']
c_link_args = ['-mmacosx-version-min=26.0']
cpp_link_args = ['-mmacosx-version-min=26.0']
""" % shutil.which(env.get("PKG_CONFIG", "pkg-config"), path=env["PATH"]))
mb = a.work / "mesa-x86_64"
run(
    [
        "meson",
        "setup",
        mb,
        mesa,
        "--cross-file",
        cross,
        *common,
        "-Dllvm=disabled",
        "-Dmesa-clc=system",
    ]
)
run(
    [
        "ninja",
        "-C",
        mb,
        "src/kosmickrisp/vulkan/libvulkan_kosmickrisp.dylib",
        "-j" + str(a.jobs),
    ]
)
# Configure against the exact distribution's FreeType, not Homebrew's arm64 dylib.
ftlib = a.work / "freetype-lib"
ftlib.mkdir()
(ftlib / "libfreetype.dylib").symlink_to(a.engine / "lib/libfreetype.6.dylib")
(pcs / "freetype2.pc").write_text(
    "Name: FreeType\nDescription: matched Wine FreeType\nVersion: 2.15.0\nLibs: -L"
    + str(ftlib)
    + " -lfreetype\nCflags: -I"
    + str(a.freetype_include)
    + "\n"
)
(pcs / "vulkan.pc").write_text(
    "Name: Vulkan\nDescription: pinned Vulkan SDK\nVersion: 1.4.363\nLibs: -L"
    + str(a.sdk / "lib")
    + " -lvulkan\nCflags: -I"
    + str(mesa / "include")
    + "\n"
)
wb = a.work / "wine-build"
wb.mkdir()
we = env.copy()
if a.bison:
    we["BISON"] = str(a.bison.resolve())
we.update(
    CC="/usr/bin/clang -arch x86_64 -mmacosx-version-min=26.0",
    CXX="/usr/bin/clang++ -arch x86_64 -mmacosx-version-min=26.0",
    OBJC="/usr/bin/clang -arch x86_64 -mmacosx-version-min=26.0",
    PKG_CONFIG_PATH=str(pcs),
    PKG_CONFIG_LIBDIR=str(pcs),
    MACOSX_DEPLOYMENT_TARGET="26.0",
    LDFLAGS="-L" + str(ftlib) + " -L" + str(a.sdk / "lib"),
)
run(
    [
        wine / "configure",
        "--build=x86_64-apple-darwin",
        "--enable-archs=i386,x86_64",
        "--disable-tests",
        "--without-x",
        "--without-opengl",
        "--with-vulkan",
        "--with-freetype",
        "--without-fontconfig",
        "--without-gstreamer",
        "--without-alsa",
        "--without-cups",
        "--without-sdl",
        "--without-usb",
    ],
    cwd=wb,
    env=we,
)
run(
    [
        "make",
        "-C",
        wb,
        "-j" + str(a.jobs),
        "dlls/winevulkan/winevulkan.so",
        "dlls/win32u/win32u.so",
        "dlls/winemac.drv/winemac.so",
        "dlls/ntdll/ntdll.so",
    ],
    env=we,
)
if not a.no_package:
    run(
        [
            "python3",
            repo / "scripts/graphics/package_support.py",
            "--mesa-build",
            mb,
            "--wine-build",
            wb,
            "--mesa-source",
            mesa,
            "--moltenvk-archive",
            a.moltenvk_archive,
        ]
    )
