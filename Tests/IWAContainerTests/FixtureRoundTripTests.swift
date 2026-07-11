import Foundation
import Testing
@testable import IWAContainer

/// M1 exit criteria: unpack a real Keynote-authored .key, re-encode every
/// .iwa with our codec, repack, and verify decompressed payloads are
/// identical. (Whether Keynote itself opens the result is checked by the
/// scripted smoke test, not here.)
@Suite("Fixture round-trip")
struct FixtureRoundTripTests {

    static var fixtureURLs: [URL] {
        guard let fixturesDir = Bundle.module.url(forResource: "Fixtures", withExtension: nil),
              let contents = try? FileManager.default.contentsOfDirectory(at: fixturesDir, includingPropertiesForKeys: nil)
        else { return [] }
        return contents.filter { $0.pathExtension == "key" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    @Test("at least one .key fixture is present")
    func fixturesExist() {
        #expect(!Self.fixtureURLs.isEmpty, "add a Keynote-authored .key to Tests/IWAContainerTests/Fixtures/")
    }

    @Test("every .iwa decompresses, parses into records, and reserializes byte-identically", arguments: fixtureURLs)
    func recordFramingIsByteStable(fixture: URL) throws {
        let archive = try KeyArchive.read(from: fixture)
        #expect(!archive.iwaEntries.isEmpty)
        for entry in archive.iwaEntries {
            let decompressed = try IWA.decompress(entry.data)
            let file = try IWAFile.parse(decompressed)
            #expect(!file.records.isEmpty, entry.path.isEmpty ? "" : "no records in \(entry.path)")
            #expect(file.serialize() == decompressed, "record framing not byte-stable for \(entry.path)")
        }
    }

    @Test("full unpack → recompress → repack keeps decompressed payloads identical", arguments: fixtureURLs)
    func fullRoundTrip(fixture: URL) throws {
        var archive = try KeyArchive.read(from: fixture)
        for entry in archive.iwaEntries {
            let decompressed = try IWA.decompress(entry.data)
            archive.replaceEntry(at: entry.path, with: IWA.compress(decompressed))
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("roundtrip-\(fixture.lastPathComponent)")
        try archive.write(to: outputURL)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let original = try KeyArchive.read(from: fixture)
        let rebuilt = try KeyArchive.read(from: outputURL)
        #expect(original.entries.map(\.path) == rebuilt.entries.map(\.path))

        for entry in original.entries {
            guard let rebuiltEntry = rebuilt.entry(at: entry.path) else {
                Issue.record("missing entry \(entry.path)")
                continue
            }
            if entry.isIWA {
                let a = try IWA.decompress(entry.data)
                let b = try IWA.decompress(rebuiltEntry.data)
                #expect(a == b, "decompressed payload mismatch: \(entry.path)")
            } else {
                #expect(entry.data == rebuiltEntry.data, "non-IWA entry changed: \(entry.path)")
            }
        }
    }
}
