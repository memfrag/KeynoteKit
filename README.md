# KeynoteKit

A Swift package for reading and generating Apple Keynote `.key` files.

Keynote's file format is a ZIP archive of `.iwa` files — Snappy-compressed
(with Apple's non-standard framing) Protocol Buffer messages using
undocumented, reverse-engineered schemas. KeynoteKit implements this format
natively in Swift, with the goal of enabling programmatic generation of
Keynote presentations and Keynote export from macOS apps.

## Status

Early development. Working today:

- **`IWAContainer`** — the container codec layer:
  - Raw Snappy compressor/decompressor in pure Swift
  - Apple's IWA chunk framing (4-byte headers, no stream identifier, no CRC-32C)
  - `TSP.ArchiveInfo` record framing with byte-stable reserialization
  - `.key` zip archive reading/writing (stored entries, matching Keynote's output)
- **`KeynoteSchemas`** — typed protobuf messages for all 600+ iWork archive
  types, generated with [swift-protobuf](https://github.com/apple/swift-protobuf)
  from the schemas extracted by
  [keynote-parser](https://github.com/psobot/keynote-parser) (currently
  Keynote 14.4), plus the numeric type-ID → message-type registry
- **`KeynoteModel`** — object-graph layer:
  - Parse a document into typed records; decode/mutate/re-encode any archive
    with correct `MessageInfo.length` bookkeeping
  - Document-wide text find/replace over `TSWP.StorageArchive`
  - **Slide operations**: duplicate (deep-copies the slide's `.iwa` component
    with fresh identifiers, rewriting internal references while preserving
    external style/theme references, and maintaining all package metadata),
    remove, and reorder
  - Schema-guided wire-format walking (`ReferenceRewriter` +
    generated `MessageFieldMap`) to find/rewrite every `TSP.Reference` in any
    payload without full decoding
- **`iwatool`** — CLI for inspecting, round-tripping, and rewriting `.key` files

Files unpacked, modified, and repacked through KeynoteKit open cleanly in
Keynote with styling intact (verified against Keynote-authored fixtures,
including scripted open-and-export-PDF smoke tests — including duplicated,
removed, and reordered slides).

Planned next: image replacement, shape insertion, and a template-based
document builder API.

## Usage

```sh
swift build
swift test

# Inspect a .key file
swift run iwatool info MyPresentation.key

# Unpack, re-encode every .iwa with KeynoteKit's codec, repack, verify
swift run iwatool roundtrip MyPresentation.key Repacked.key

# Print all text in a presentation
swift run iwatool text MyPresentation.key

# Replace text across a presentation
swift run iwatool replace In.key Out.key "old text" "new text"

# Slide operations (0-based indices)
swift run iwatool duplicate-slide In.key Out.key 0
swift run iwatool remove-slide In.key Out.key 2
swift run iwatool move-slide In.key Out.key 0 3
```

## Regenerating the schemas

The vendored `.proto` files (see `proto/`) come from keynote-parser, which
extracts them from the Keynote application binary. To regenerate the Swift
code for a new schema version:

```sh
PROTOC=/path/to/protoc PROTOC_GEN_SWIFT=/path/to/protoc-gen-swift \
  scripts/gen-protos.sh 14.4
```

## Acknowledgements

The format understanding builds on prior reverse-engineering work:

- [psobot/keynote-parser](https://github.com/psobot/keynote-parser)
- [obriensp/iWorkFileFormat](https://github.com/obriensp/iWorkFileFormat)
- [Reverse Engineering iWork](https://andrews.substack.com/p/reverse-engineering-iwork) by Andrew Sampson
- [eth-siplab/SVG2Keynote-lib](https://github.com/eth-siplab/SVG2Keynote-lib)

Keynote is a trademark of Apple Inc. This project is not affiliated with or
endorsed by Apple. The file format is undocumented and may change with any
Keynote release.
