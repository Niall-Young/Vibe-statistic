#!/usr/bin/env python3
"""Offline checks: code signatures, relocation, isolated runtimes and helpers."""
import json
import os
import pathlib
import platform
import subprocess
import sys
import tempfile

app = pathlib.Path(sys.argv[1]).resolve()
resources = app / 'Contents/Resources'
magic = {b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca'}
seen = set()
for path in sorted(app.rglob('*')):
    if not path.is_file() or path.is_symlink(): continue
    with path.open('rb') as f: header = f.read(4)
    if header not in magic: continue
    real = path.resolve()
    if real in seen: continue
    seen.add(real)
    dependencies = subprocess.check_output(['otool', '-L', str(path)], text=True).splitlines()[1:]
    identities = subprocess.check_output(['otool', '-D', str(path)], text=True).splitlines()[1:]
    for index, line in enumerate(dependencies):
        dependency = line.strip().split(' (', 1)[0]
        if index == 0 and dependency in identities: continue
        if not dependency.startswith(('/usr/lib/', '/System/Library/', '@')):
            raise SystemExit('Non-portable dependency: ' + str(path.relative_to(app)) + ': ' + dependency)
    architectures = subprocess.check_output(['lipo', '-archs', str(path)], text=True).split()
    if 'arm64' not in architectures and 'arm64e' not in architectures:
        raise SystemExit('Missing Apple Silicon code: ' + str(path.relative_to(app)))
    if '--sign' in sys.argv:
        subprocess.run(['codesign', '--force', '--sign', '-', str(path)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
if '--sign' in sys.argv: raise SystemExit(0)
subprocess.run(['codesign', '--verify', '--deep', str(app)], check=True)
for name in ('AGENTS.md', '.env', 'usage.store', 'verification.json'):
    if any(app.rglob(name)): raise SystemExit('Unexpected packaged file: ' + name)
with tempfile.TemporaryDirectory(prefix='vibe-offline-') as directory:
    environment = {'HOME': directory, 'PATH': '/usr/bin:/bin', 'LANG': 'en_US.UTF-8',
                   'SSL_CERT_FILE': str(resources / 'Runtime/cacert.pem')}
    python = resources / 'Runtime/python/bin/python3'
    node = resources / 'Runtime/node/bin/node'
    subprocess.run([str(python), '-I', '-B', '-c', 'import ssl,sqlite3,ctypes,platform; assert platform.machine()=="arm64"; assert ssl.create_default_context().cert_store_stats()["x509_ca"] > 0'], env=environment, check=True)
    subprocess.run([str(node), '-e', 'if(process.arch!=="arm64")process.exit(1)'], env=environment, check=True)
    script = 'import sys;sys.path.insert(0,sys.argv[1]);import bridge;import pyte,wcwidth;assert bridge.parse_glm({"limits":[{"type":"TOKENS_LIMIT","percentage":25}]})[0]["value"]==75'
    subprocess.run([str(python), '-I', '-B', '-c', script, str(resources / 'Helpers')], env=environment, check=True)
    # No account/secret and no model task: the bridge must fail cleanly in this relocated bundle.
    sandbox = ['/usr/bin/sandbox-exec']
    for name, folder in [('DESKTOP', 'Desktop'), ('DOCUMENTS', 'Documents'), ('DOWNLOADS', 'Downloads'), ('PICTURES', 'Pictures'), ('MOVIES', 'Movies'), ('MUSIC', 'Music'), ('HOME_GIT', '.git')]:
        sandbox += ['-D', name + '=' + str(pathlib.Path(directory) / folder)]
    sandbox += ['-D', 'APP_RESOURCES=' + str(resources), '-f', str(resources / 'Helpers/query.sb')]
    result = subprocess.run(sandbox + [str(python), '-I', '-B', str(resources / 'Helpers/bridge.py')],
        input=json.dumps({'provider': 'glm', 'explicitSecret': 'true'}), text=True, capture_output=True, env=environment, check=True, timeout=15)
    payload = json.loads(result.stdout)
    if payload.get('errorCode') != 'auth': raise SystemExit('Offline bridge smoke check failed')
if any(app.rglob('__pycache__')): raise SystemExit('Python wrote bytecode into the signed bundle')
subprocess.run(['codesign', '--verify', '--deep', str(app)], check=True)
print('Bundle verified: signatures, arm64, portable dependencies, Python TLS, Node, offline bridge')
