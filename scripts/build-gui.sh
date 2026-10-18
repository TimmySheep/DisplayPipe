#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# These suites are offline/read-only. No GUI launch and no live setter.
sh scripts/backend-test.sh
sh scripts/test-gui.sh
/usr/bin/python3 -B scripts/package-app.py
/usr/bin/python3 -B scripts/test-icon.py -v
/usr/bin/python3 -B scripts/test-package.py -v
