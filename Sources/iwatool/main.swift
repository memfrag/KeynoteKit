import Foundation
import IWAContainer

let usage = """
usage:
  iwatool info <file.key>              list entries, records per .iwa component
  iwatool roundtrip <in.key> <out.key> unpack, re-encode every .iwa, repack
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count >= 3 else { fail(usage) }

let command = arguments[1]
let inputURL = URL(fileURLWithPath: arguments[2])

switch command {
case "info":
    let archive = try KeyArchive.read(from: inputURL)
    for entry in archive.entries {
        if entry.isIWA {
            let decompressed = try IWA.decompress(entry.data)
            let file = try IWAFile.parse(decompressed)
            let types = file.records.compactMap(\.messageTypes.first)
            print("\(entry.path): \(entry.data.count) bytes compressed, \(decompressed.count) decompressed, \(file.records.count) records, types \(Set(types).sorted())")
        } else {
            print("\(entry.path): \(entry.data.count) bytes")
        }
    }

case "roundtrip":
    guard arguments.count >= 4 else { fail(usage) }
    let outputURL = URL(fileURLWithPath: arguments[3])
    var archive = try KeyArchive.read(from: inputURL)
    for entry in archive.iwaEntries {
        let decompressed = try IWA.decompress(entry.data)
        let file = try IWAFile.parse(decompressed)
        let reserialized = file.serialize()
        guard reserialized == decompressed else {
            fail("record framing not byte-stable for \(entry.path)")
        }
        archive.replaceEntry(at: entry.path, with: IWA.compress(reserialized))
    }
    try archive.write(to: outputURL)

    // Verify: decompressed payloads of the output must match the input.
    let inArchive = try KeyArchive.read(from: inputURL)
    let outArchive = try KeyArchive.read(from: outputURL)
    for entry in inArchive.iwaEntries {
        guard let outEntry = outArchive.entry(at: entry.path) else {
            fail("missing entry in output: \(entry.path)")
        }
        let original = try IWA.decompress(entry.data)
        let rebuilt = try IWA.decompress(outEntry.data)
        guard original == rebuilt else {
            fail("payload mismatch after roundtrip: \(entry.path)")
        }
    }
    print("roundtrip OK: \(outArchive.entries.count) entries, decompressed payloads identical")

default:
    fail(usage)
}
