#!/usr/bin/env python3
"""Release gate: download advertised assets and verify bytes before feed publication."""
import argparse
import base64
import hashlib
import json
import tempfile
import subprocess
from pathlib import Path
import urllib.request
import xml.etree.ElementTree as ET

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--appcast', type=Path)
p.add_argument('--runtime', type=Path)
a = p.parse_args()
assert a.appcast or a.runtime, 'Provide a feed'
assets = []
if a.appcast:
    for item in ET.parse(a.appcast).iter('enclosure'):
        assert item.get('{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature'), 'Missing Sparkle signature'
        assets.append((item.get('url'), int(item.get('length')), None, item.get('{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature')))
if a.runtime:
    envelope = json.loads(a.runtime.read_text())
    # Signing verification is performed by the client/probe and RuntimeSigner;
    # this publishing gate verifies that the advertised public bytes actually exist.
    payload = json.loads(base64.b64decode(envelope['payload']))
    for runtime in payload['sets']:
        for item in runtime['packages']:
            assets.append((item['url'], item['size'], item['sha256'], None))
for url, expected_size, expected_digest, signature in assets:
    assert url.startswith('https://github.com/') and '/releases/download/' in url, 'Expected immutable release asset URL'
    digest = hashlib.sha256()
    size = 0
    with tempfile.TemporaryDirectory(prefix='ScotchPublicAsset-') as temp:
        artifact = Path(temp) / 'asset'
        with urllib.request.urlopen(url, timeout=60) as stream, artifact.open('wb') as output:
            while chunk := stream.read(1024 * 1024):
                output.write(chunk)
                digest.update(chunk)
                size += len(chunk)
        assert size == expected_size, f'Size mismatch: {url}'
        if expected_digest:
            assert digest.hexdigest() == expected_digest.lower(), f'Checksum mismatch: {url}'
        if signature:
            subprocess.run(['swift', str(Path(__file__).parent / 'VerifyArchive.swift'), str(artifact), signature], check=True)
    print(f'Verified {url}')
