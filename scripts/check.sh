#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build
xcrun swiftc DisplayProbe.swift -o .build/DisplayProbe
xcrun clang -fobjc-arc -framework Foundation -framework IOKit EDIDProbe.m -o .build/EDIDProbe
.build/DisplayProbe
.build/EDIDProbe
CARGO="${HOME}/.cargo/bin/cargo"
"$CARGO" test --offline --locked --manifest-path pipecap-review/Cargo.toml
