#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/dist/Vibe Statistics.app"
if pgrep -x VibeStatistics >/dev/null; then
  printf '%s\n' 'Quit Vibe Statistics before running the verification process.' >&2
  exit 1
fi
# Finder may add its bundle flag to the directory after launch; verify signed code/resources.
codesign --verify --deep "$APP"
export VIBE_VERIFY_DIR="$PWD/.local/verification"
"$APP/Contents/MacOS/VibeStatistics" --verify-ui
/usr/bin/python3 - <<'PY'
import json,pathlib,sys
p=pathlib.Path('.local/verification/verification.json')
d=json.loads(p.read_text());print(json.dumps(d,indent=2))
if not d['providers'] or d['connected'] != len(d['providers']) or d['storageError'] != 'none': sys.exit(1)
PY
