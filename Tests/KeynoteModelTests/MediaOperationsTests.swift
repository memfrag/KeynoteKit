import CryptoKit
import Foundation
import Testing
@testable import KeynoteModel
import KeynoteSchemas

@Suite("Media operations")
struct MediaOperationsTests {

    static var fixtureURL: URL {
        Bundle.module.url(forResource: "Fixtures/imagedeck", withExtension: "key")!
    }

    static var blueImageURL: URL {
        Bundle.module.url(forResource: "Fixtures/blue", withExtension: "png")!
    }

    @Test("replaceImage swaps bytes and keeps digests consistent")
    func replaceImageConsistency() throws {
        var document = try KeynoteDocument(contentsOf: Self.fixtureURL)
        let blue = try Data(contentsOf: Self.blueImageURL)

        let replaced = try document.replaceImage(named: "red.png", with: blue)
        #expect(replaced.count == 2, "expected full-size + -small- preview, got \(replaced)")

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("media-replaced.key")
        try document.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let reread = try KeynoteDocument(contentsOf: url)

        // The full-size file is exactly the new image; the preview is a
        // distinct re-render (never byte-identical — a shared digest between
        // two DataInfo entries crashes Keynote's persistence layer).
        let mainBytes = try #require(reread.dataForEntry(at: "Data/red-9075.png"))
        #expect(mainBytes == blue)
        let previewBytes = try #require(reread.dataForEntry(at: "Data/red-small-9077.png"))
        #expect(previewBytes != blue, "preview must not duplicate the full-size digest")
        #expect(!previewBytes.isEmpty)

        // Every DataInfo digest matches the SHA-1 of its materialized file,
        // and every digest is present in DocumentMetadata's list.
        let metadataRecord = try #require(
            reread.components.flatMap(\.records).first { $0.primaryType == 11006 }
        )
        let metadata = try metadataRecord.decode(TSP_PackageMetadata.self)
        let documentMetadataRecord = try #require(
            reread.components.flatMap(\.records).first { $0.primaryType == 11011 }
        )
        let documentMetadata = try documentMetadataRecord.decode(TSP_DocumentMetadata.self)
        let knownDigests = Set(documentMetadata.dataPropertiesV1.properties.map(\.digest))

        var verified = 0
        for info in metadata.datas where !info.fileName.isEmpty {
            let bytes = try #require(reread.dataForEntry(at: "Data/" + info.fileName), Comment(rawValue: info.fileName))
            #expect(Data(Insecure.SHA1.hash(data: bytes)) == info.digest, "digest mismatch: \(info.fileName)")
            #expect(knownDigests.contains(info.digest), "digest missing from DocumentMetadata: \(info.fileName)")
            verified += 1
        }
        #expect(verified >= 2)
    }

    @Test("replacing a nonexistent image throws")
    func missingImage() throws {
        var document = try KeynoteDocument(contentsOf: Self.fixtureURL)
        #expect(throws: MediaOperationError.self) {
            try document.replaceImage(named: "nope.png", with: Data([1, 2, 3]))
        }
    }
}
