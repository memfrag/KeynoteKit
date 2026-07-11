# ``IWAContainer``

The codec for Keynote's container format: Snappy compression, IWA record
framing, and the `.key` zip archive.

## Overview

`IWAContainer` is the lowest layer of KeynoteKit. It has no knowledge of
slides or Keynote semantics — it reads and writes the bytes:

- ``KeyArchive`` — the `.key` file at the zip level: ordered entries,
  written back with stored (uncompressed) entries, matching Keynote's own
  output.
- ``IWA`` — Apple's chunk framing over Snappy: a sequence of
  `[type byte 0x00, 24-bit little-endian length]` headers, each followed by
  a raw Snappy block. There is no stream identifier and no CRC — this is
  *not* the standard Snappy framing format.
- ``Snappy`` — a pure-Swift raw Snappy compressor/decompressor.
- ``IWAFile`` / ``ArchiveRecord`` — the record layer: each `Index/*.iwa`
  component is a sequence of records, each a varint-length-prefixed
  `TSP.ArchiveInfo` header followed by that record's protobuf message
  payloads. Untouched records reserialize byte-identically.
- ``ProtoScanner`` — a minimal protobuf wire-format reader used to peek
  inside `ArchiveInfo` without generated schemas.

```swift
import IWAContainer

let archive = try KeyArchive.read(from: URL(filePath: "Deck.key"))
for entry in archive.iwaEntries {
    let decompressed = try IWA.decompress(entry.data)
    let file = try IWAFile.parse(decompressed)
    print(entry.path, file.records.count, "records")
}
```

## The .key format in one paragraph

A `.key` document is a ZIP archive containing `Index/*.iwa` components
(the object graph, as Snappy-compressed protobuf records), `Data/*` media
files, `Metadata/*` property lists, and preview images. Objects carry
document-unique integer identifiers and reference each other with
`TSP.Reference` messages; each component's membership, cross-component
references, and media usage are tracked in a `PackageMetadata` archive
inside `Index/Metadata.iwa`. The protobuf schemas are Apple-private and
reverse-engineered from the Keynote binary (vendored under `proto/` and
compiled by `scripts/gen-protos.sh`); the only authoritative validator for
a produced file is Keynote itself.

Higher layers build on this: `KeynoteSchemas` provides the generated
message types and the type-id registry, and `KeynoteModel` provides the
typed object graph and editing operations.

## Topics

### The zip layer

- ``KeyArchive``
- ``KeyArchiveError``

### Compression

- ``Snappy``
- ``IWA``
- ``SnappyError``

### Records

- ``IWAFile``
- ``ArchiveRecord``
- ``IWAFileError``

### Wire format

- ``ProtoScanner``
- ``ProtoScanError``
