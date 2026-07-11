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
  - **Image replacement**: swaps a `Data/` image in place, re-renders the
    Keynote-generated preview at its original size, and updates the SHA-1
    digests in both `PackageMetadata` and `DocumentMetadata`
  - Schema-guided wire-format walking (`ReferenceRewriter` +
    generated `MessageFieldMap`) to find/rewrite every `TSP.Reference` in any
    payload without full decoding
  - Per-slide title/body reading and editing (`slideTitle`/`setSlideText`),
    navigating `SlideArchive` → placeholder → `StorageArchive`
- **`KeynoteBuilder`** — the high-level API: describe a `Presentation` of
  `Slide`s (title + body) declaratively and write it to a `.key`. Uses a
  template strategy — an embedded seed deck carrying a real Keynote theme,
  masters, and stylesheets is grown/shrunk to the requested slide count and
  filled in, so output inherits genuine Keynote styling. Point it at your own
  `.key` template to use a branded theme.
- **`iwatool`** — CLI for inspecting, round-tripping, and rewriting `.key` files

Files generated or modified through KeynoteKit open cleanly in Keynote with
styling intact (verified against Keynote-authored fixtures, including scripted
open-and-export-PDF smoke tests — text replacement, image replacement, and
duplicated / removed / reordered slides, plus full decks built from scratch).

Planned next: shapes and tables (M4), then builds / transitions / charts (M5).

## Generating a presentation

```swift
import KeynoteBuilder

let deck = Presentation {
    Slide(title: "KeynoteKit", body: "A Swift package for generating Keynote files")
    Slide(title: "How it works", body: "Start from a themed seed\nFill in each slide")
    Slide(title: "Status", body: "Milestones 1–3 complete")
}

let writer = try KeynoteWriter()          // or KeynoteWriter(templateURL: myTheme)
try writer.write(deck, to: URL(filePath: "Deck.key"))
```

The builder returns a `KeynoteDocument` from `build(_:)` if you want to apply
further edits (e.g. `replaceImage`) before writing.

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

# Replace an image (by its original file name)
swift run iwatool list-media In.key
swift run iwatool replace-image In.key Out.key photo.jpg new-photo.jpg

# Build a deck from a text outline ("# " starts a slide; other lines are body)
swift run iwatool build outline.txt Deck.key
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
