# KeynoteKit

A Swift package for reading and generating Apple Keynote `.key` files.

Keynote's file format is a ZIP archive of `.iwa` files — Snappy-compressed
(with Apple's non-standard framing) Protocol Buffer messages using
undocumented, reverse-engineered schemas. KeynoteKit implements this format
natively in Swift, with the goal of enabling programmatic generation of
Keynote presentations and Keynote export from macOS apps.

## Status

Early development. Working today (milestone 1 — codec proof):

- **`IWAContainer`** — the container codec layer:
  - Raw Snappy compressor/decompressor in pure Swift
  - Apple's IWA chunk framing (4-byte headers, no stream identifier, no CRC-32C)
  - `TSP.ArchiveInfo` record framing with byte-stable reserialization
  - `.key` zip archive reading/writing (stored entries, matching Keynote's output)
- **`iwatool`** — CLI for inspecting and round-tripping `.key` files

A file unpacked and repacked through KeynoteKit's own codec opens cleanly in
Keynote (verified against Keynote-authored fixtures, including scripted
open-and-export-PDF smoke tests).

Planned next: typed protobuf schema layer (generated from
[keynote-parser](https://github.com/psobot/keynote-parser)'s extracted
schemas), object-graph model, and a template-based document builder API.

## Usage

```sh
swift build
swift test

# Inspect a .key file
swift run iwatool info MyPresentation.key

# Unpack, re-encode every .iwa with KeynoteKit's codec, repack, verify
swift run iwatool roundtrip MyPresentation.key Repacked.key
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
