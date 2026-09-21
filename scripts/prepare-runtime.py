#!/usr/bin/env python3
"""Download verified, relocatable Apple Silicon runtimes. Build-time only."""
import hashlib
import json
import pathlib
import shutil
import subprocess
import tarfile
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
lock_bytes = (ROOT / 'scripts/runtime-lock.json').read_bytes()
lock = json.loads(lock_bytes)
cache = ROOT / '.build/runtime-downloads'
output = ROOT / '.build/Runtime'
cache.mkdir(parents=True, exist_ok=True)
marker = hashlib.sha256(lock_bytes).hexdigest()
if (output / '.runtime-lock').exists() and (output / '.runtime-lock').read_text() == marker:
    raise SystemExit(0)

def sha(path):
    with path.open('rb') as stream:
        digest = hashlib.sha256()
        for block in iter(lambda: stream.read(1024 * 1024), b''): digest.update(block)
        return digest.hexdigest()

with tempfile.TemporaryDirectory(dir=ROOT / '.build', prefix='runtime-') as stage_name:
    stage = pathlib.Path(stage_name)
    for name, entry in lock.items():
        archive = cache / (name + '.tar.gz')
        if not archive.exists() or sha(archive) != entry['sha256']:
            partial = archive.with_suffix('.part')
            subprocess.run(['curl', '-fLsS', '--retry', '3', '--max-time', '600', entry['url'], '-o', str(partial)], check=True)
            if sha(partial) != entry['sha256']: raise RuntimeError(name + ' checksum mismatch')
            partial.replace(archive)
        unpack = stage / ('unpack-' + name)
        unpack.mkdir()
        # The release archive is checksum verified; also reject absolute/traversal members.
        with tarfile.open(archive) as tar:
            for member in tar.getmembers():
                path = pathlib.PurePosixPath(member.name)
                if path.is_absolute() or '..' in path.parts: raise RuntimeError('Unsafe runtime archive')
                if member.issym() or member.islnk():
                    target = (unpack / member.name).parent / member.linkname
                    if not str(target.resolve()).startswith(str(unpack.resolve()) + '/'):
                        raise RuntimeError('Unsafe runtime symlink')
            tar.extractall(unpack)
        folders = list(unpack.iterdir())
        if len(folders) != 1: raise RuntimeError('Unexpected runtime layout')
        shutil.move(str(folders[0]), str(stage / name))
        unpack.rmdir()
    (stage / '.runtime-lock').write_text(marker)
    shutil.copy2(ROOT / 'scripts/runtime-lock.json', stage / 'runtime-lock.json')
    if output.exists(): shutil.rmtree(output)
    shutil.copytree(stage, output, symlinks=True)
print(output)
