#!/usr/bin/env python3
"""Prepare complete Scotch/Wine/Mesa source and build instructions for the DMG."""

import argparse, copy, hashlib, json, os, subprocess, tarfile, tempfile, urllib.request
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument(
    "--mesa-archive",
    type=Path,
    default=Path(".build/graphics-sources/mesa-cbc51df.tar.gz"),
)
p.add_argument(
    "--wine-archive", type=Path, default=Path(".build/wineforge-source/0.6.0.3.tar.gz")
)
p.add_argument(
    "--output",
    type=Path,
    default=Path(".build/graphics-support/ScotchGraphicsSources.tar.xz"),
)
a = p.parse_args()
repo = Path(__file__).resolve().parents[2]
os.chdir(repo)
lock = json.loads((repo / "scripts/graphics/sources.json").read_text())


def sha(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        while b := f.read(4 * 1024 * 1024):
            h.update(b)
    return h.hexdigest()


for path, key in [(a.mesa_archive, "mesa"), (a.wine_archive, "wine")]:
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        with urllib.request.urlopen(
            urllib.request.Request(
                lock[key]["url"], headers={"User-Agent": "Scotch-release-builder"}
            ),
            timeout=120,
        ) as src, tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as out:
            temporary = Path(out.name)
            while block := src.read(4 * 1024 * 1024):
                out.write(block)
        temporary.replace(path)
    if sha(path) != lock[key]["sha256"]:
        raise SystemExit("Source checksum mismatch: " + str(path))
paths = sorted(
    set(
        subprocess.check_output(
            ["git", "ls-files", "-z", "-c", "-o", "--exclude-standard"]
        )
        .decode()
        .split("\0")
    )
    - {""}
)
paths = [Path(x) for x in paths if Path(x).is_file() or Path(x).is_symlink()]
h = hashlib.sha256()
for path in paths:
    h.update(path.as_posix().encode())
    h.update((os.readlink(path) if path.is_symlink() else sha(path)).encode())
h.update(lock["mesa"]["sha256"].encode())
h.update(lock["wine"]["sha256"].encode())
fingerprint = h.hexdigest()
receipt = a.output.with_suffix(".json")
if a.output.exists() and receipt.exists():
    previous = json.loads(receipt.read_text())
    if previous.get("inputSHA256") == fingerprint and previous.get("sha256") == sha(
        a.output
    ):
        print("Using verified source archive", a.output)
        raise SystemExit(0)
a.output.parent.mkdir(parents=True, exist_ok=True)
# xz is a build-time tool, never an installed runtime dependency.
with tempfile.NamedTemporaryFile(dir=a.output.parent, delete=False) as output:
    temporary = Path(output.name)
    xz = subprocess.Popen(
        ["xz", "-T4", "-3", "-c"], stdin=subprocess.PIPE, stdout=output
    )
    try:
        with tarfile.open(fileobj=xz.stdin, mode="w|") as target:
            for archive, dirname in [
                (a.wine_archive, "WineForge-0.6.0.3"),
                (a.mesa_archive, "Mesa-" + lock["mesa"]["commit"]),
            ]:
                with tarfile.open(archive) as source:
                    prefix = source.getmembers()[0].name.split("/")[0]
                    for member in source:
                        info = copy.copy(member)
                        suffix = member.name[len(prefix) :].lstrip("/")
                        info.name = dirname + ("/" + suffix if suffix else "")
                        if info.islnk():
                            info.linkname = (
                                dirname + "/" + info.linkname[len(prefix) :].lstrip("/")
                            )
                        info.uid = info.gid = info.mtime = 0
                        info.uname = info.gname = ""
                        info.pax_headers = {}
                        target.addfile(
                            info,
                            source.extractfile(member) if member.isfile() else None,
                        )
            for path in paths:
                info = target.gettarinfo(path, arcname="Scotch/" + path.as_posix())
                info.uid = info.gid = info.mtime = 0
                info.uname = info.gname = ""
                info.pax_headers = {}
                with (
                    path.open("rb") if info.isfile() else open(os.devnull, "rb")
                ) as data:
                    target.addfile(info, data if info.isfile() else None)
        xz.stdin.close()
        if xz.wait() != 0:
            raise RuntimeError("xz failed")
    except BaseException:
        xz.kill()
        xz.wait()
        temporary.unlink(missing_ok=True)
        raise
    temporary.replace(a.output)
receipt.write_text(
    json.dumps({"inputSHA256": fingerprint, "sha256": sha(a.output)}, indent=2) + "\n"
)
print("Created", a.output, a.output.stat().st_size, "bytes", sha(a.output))
