#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
sh scripts/backend-build.sh
cargo test --offline --locked --manifest-path backend/edid-core/Cargo.toml
python3 -m unittest discover -s tests/backend -v
# No setter command is ever used by this script.
backend/build/DisplayPipeIO write-preflight
