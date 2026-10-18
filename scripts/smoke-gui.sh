#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# Independent of the GUI event loop; run build-gui.sh first.
exec .build/DisplayPipe.app/Contents/MacOS/DisplayPipe --smoke-json
