import Foundation
import Testing
@testable import KeynoteModel
import KeynoteSchemas

@Suite("KeynoteDocument object graph")
struct KeynoteDocumentTests {

    static var fixtureURL: URL {
        Bundle.module.url(forResource: "Fixtures/basic", withExtension: "key")!
    }

    @Test("decodes every record's primary message through the registry")
    func decodesAllRecords() throws {
        let document = try KeynoteDocument(contentsOf: Self.fixtureURL)
        var decoded = 0
        var unknownTypes: Set<UInt32> = []
        for component in document.components {
            for record in component.records {
                do {
                    _ = try record.decodeMessage()
                    decoded += 1
                } catch ObjectRecordError.unknownMessageType(let type) {
                    unknownTypes.insert(type)
                }
            }
        }
        #expect(decoded > 100)
        #expect(unknownTypes.isEmpty, "types missing from TSPRegistry: \(unknownTypes.sorted())")
    }

    @Test("root record (ID 1) is a KN.DocumentArchive")
    func rootIsDocumentArchive() throws {
        let document = try KeynoteDocument(contentsOf: Self.fixtureURL)
        let root = try #require(document.record(withIdentifier: 1))
        #expect(root.primaryType == 1)
        let message = try root.decodeMessage()
        #expect(message is KN_DocumentArchive)
    }

    @Test("write without mutations preserves decompressed payloads")
    func cleanWriteIsStable() throws {
        let document = try KeynoteDocument(contentsOf: Self.fixtureURL)
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("clean-write.key")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        try document.write(to: outputURL)

        let reread = try KeynoteDocument(contentsOf: outputURL)
        #expect(reread.components.map(\.path) == document.components.map(\.path))
        for (a, b) in zip(document.components, reread.components) {
            #expect(a.records.count == b.records.count, "record count changed in \(a.path)")
            for (x, y) in zip(a.records, b.records) {
                #expect(x.payloads == y.payloads, "payload changed in \(a.path)")
            }
        }
    }

    @Test("finds the fixture's title text")
    func findsText() throws {
        let document = try KeynoteDocument(contentsOf: Self.fixtureURL)
        let text = TextReplacement.allText(in: document)
        #expect(text.contains { $0.contains("KeynoteKit Fixture") })
    }

    @Test("replaces text and survives a write/read cycle")
    func replaceRoundTrip() throws {
        var document = try KeynoteDocument(contentsOf: Self.fixtureURL)
        let count = try TextReplacement.replace("KeynoteKit Fixture", with: "Rewritten in Swift", in: &document)
        #expect(count >= 1)

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("replaced.key")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        try document.write(to: outputURL)

        let reread = try KeynoteDocument(contentsOf: outputURL)
        let text = TextReplacement.allText(in: reread)
        #expect(text.contains { $0.contains("Rewritten in Swift") })
        #expect(!text.contains { $0.contains("KeynoteKit Fixture") })
    }
}
