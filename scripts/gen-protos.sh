#!/bin/bash
# Generates Sources/KeynoteSchemas/Generated/<version>/ from proto/<version>/.
#
# The .proto files are vendored from psobot/keynote-parser (MIT), which
# extracts them from the Keynote application binary. See proto/<version>/.
#
# Requirements:
#   - protoc            (https://github.com/protocolbuffers/protobuf/releases)
#   - protoc-gen-swift  (build from https://github.com/apple/swift-protobuf:
#                        swift build -c release --product protoc-gen-swift)
#
# Usage:
#   PROTOC=/path/to/protoc PROTOC_GEN_SWIFT=/path/to/protoc-gen-swift \
#     scripts/gen-protos.sh [version]
set -euo pipefail

VERSION="${1:-14.4}"
PROTOC="${PROTOC:-protoc}"
PROTOC_GEN_SWIFT="${PROTOC_GEN_SWIFT:-protoc-gen-swift}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROTO_DIR="$REPO_ROOT/proto/$VERSION"
OUT_DIR="$REPO_ROOT/Sources/KeynoteSchemas/Generated/$VERSION"

mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR"/*.pb.swift

"$PROTOC" \
    --plugin=protoc-gen-swift="$PROTOC_GEN_SWIFT" \
    --swift_out="$OUT_DIR" \
    --swift_opt=Visibility=Public \
    -I "$PROTO_DIR" \
    "$PROTO_DIR"/*.proto

echo "Generated $(ls "$OUT_DIR" | wc -l | tr -d ' ') files in $OUT_DIR"

python3 "$REPO_ROOT/scripts/gen-registry.py" "$VERSION"
