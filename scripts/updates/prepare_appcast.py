#!/usr/bin/env python3
"""Prepare a signed appcast locally. Never publishes anything."""
import argparse
from pathlib import Path
import shutil
import subprocess
import xml.etree.ElementTree as ET

p = argparse.ArgumentParser(description=__doc__)
p.add_argument("--archive", type=Path, required=True)
p.add_argument("--tag", required=True)
p.add_argument("--tools", type=Path, default=Path('.build/updater-tools/bin'))
p.add_argument("--output", type=Path, required=True)
p.add_argument("--notes", type=Path)
p.add_argument("--download-prefix", help="Override only for authenticated local update tests")
a = p.parse_args()
if not a.tag.startswith('v') or '/' in a.tag or '..' in a.tag:
    p.error('Expected a v-prefixed release tag')
a.output.mkdir(parents=True, exist_ok=True)
archive = a.output / a.archive.name
if a.archive.resolve() != archive.resolve():
    shutil.copy2(a.archive, archive)
if a.notes:
    shutil.copy2(a.notes, archive.with_suffix('.txt'))
prefix = a.download_prefix or f'https://github.com/S3bRR/Scotch/releases/download/{a.tag}/'
subprocess.run([str(a.tools / 'generate_appcast'), '--download-url-prefix', prefix, '--embed-release-notes', str(a.output)], check=True)
subprocess.run([str(a.tools / 'sign_update'), '--verify', str(a.output / 'appcast.xml')], check=True)
root = ET.parse(a.output / 'appcast.xml').getroot()
ns = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
for enclosure in root.iter('enclosure'):
    assert enclosure.get(ns + 'edSignature'), 'Missing archive signature'
    assert enclosure.get('url', '').startswith(prefix), 'Unexpected archive URL'
print(f'Signed feed prepared at {a.output / "appcast.xml"}. Upload and publish only after validation.')
