#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p backend/build
clang -Wall -Wextra -Werror -fobjc-arc backend/DisplayPipeIO.m -framework Foundation -framework IOKit -framework CoreGraphics -o backend/build/DisplayPipeIO
cargo build --offline --locked --release --manifest-path backend/edid-core/Cargo.toml
python3 -m py_compile backend/displaypipe.py
