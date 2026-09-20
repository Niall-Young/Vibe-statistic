#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export PYTHONDONTWRITEBYTECODE=1
/usr/bin/python3 -m unittest discover -s Tests -p 'test_*.py' -v
swift test
