import Foundation
import Testing
@testable import KeynoteModel
import KeynoteSchemas

@Suite("Slide operations")
struct SlideOperationsTests {

    static var oneSlideURL: URL {
        Bundle.module.url(forResource: "Fixtures/basic", withExtension: "key")!
    }

    static var twoSlideURL: URL {
        Bundle.module.url(forResource: "Fixtures/twoslides", withExtension: "key")!
    }

    private func writeAndReread(_ document: KeynoteDocument, as name: String) throws -> KeynoteDocument {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try document.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try KeynoteDocument(contentsOf: url)
    }

    @Test("duplicateSlide adds a slide, a component, and consistent metadata")
    func duplicate() throws {
        var document = try KeynoteDocument(contentsOf: Self.oneSlideURL)
        #expect(document.slideCount == 1)
        let newRootID = try document.duplicateSlide(at: 0)
        #expect(document.slideCount == 2)

        let reread = try writeAndReread(document, as: "op-duplicate.key")
        #expect(reread.slideCount == 2)

        // The new component exists, is registered, and its root decodes.
        let newPath = "Index/Slide-\(newRootID).iwa"
        let component = try #require(reread.components.first { $0.path == newPath })
        #expect(component.records.first?.identifier == newRootID)
        _ = try component.records[0].decode(KN_SlideArchive.self)

        let metadataRecord = try #require(
            reread.components.flatMap(\.records).first { $0.primaryType == 11006 }
        )
        let metadata = try metadataRecord.decode(TSP_PackageMetadata.self)
        #expect(metadata.components.contains { $0.identifier == newRootID && $0.locator == "Slide-\(newRootID)" })

        // Every identifier in the document is unique and within the allocator bound.
        var seen: Set<UInt64> = []
        for component in reread.components {
            for record in component.records {
                if let identifier = record.identifier {
                    #expect(!seen.contains(identifier), "duplicate identifier \(identifier)")
                    seen.insert(identifier)
                    #expect(identifier <= metadata.lastObjectIdentifier)
                }
            }
        }
    }

    @Test("duplicated slide resolves all internal references to the clone, not the source")
    func duplicateRewritesInternalReferences() throws {
        var document = try KeynoteDocument(contentsOf: Self.oneSlideURL)
        let newRootID = try document.duplicateSlide(at: 0)

        let newComponent = try #require(document.components.first { $0.path == "Index/Slide-\(newRootID).iwa" })
        let cloneIDs = Set(newComponent.records.compactMap(\.identifier))
        let sourceComponent = try #require(document.components.first { $0.path.hasPrefix("Index/Slide-") && $0.path != "Index/Slide-\(newRootID).iwa" })
        let sourceIDs = Set(sourceComponent.records.compactMap(\.identifier))

        for record in newComponent.records {
            for (index, info) in record.info.messageInfos.enumerated() {
                guard let typeName = TSPRegistry.protoNames[info.type] else { continue }
                let references = try ReferenceRewriter.collectReferences(
                    in: record.payloads[index], typeName: typeName
                )
                for reference in references {
                    #expect(
                        !sourceIDs.contains(reference) || cloneIDs.contains(reference),
                        "clone record \(record.identifier ?? 0) still references source object \(reference)"
                    )
                }
            }
        }
    }

    @Test("removeSlide drops the node, component, and metadata entries")
    func remove() throws {
        var document = try KeynoteDocument(contentsOf: Self.twoSlideURL)
        #expect(document.slideCount == 2)
        let componentCountBefore = document.components.count

        try document.removeSlide(at: 0)
        let reread = try writeAndReread(document, as: "op-remove.key")
        #expect(reread.slideCount == 1)
        #expect(reread.components.count == componentCountBefore - 1)
    }

    @Test("removing the last slide is refused")
    func removeLast() throws {
        var document = try KeynoteDocument(contentsOf: Self.oneSlideURL)
        #expect(throws: SlideOperationError.self) {
            try document.removeSlide(at: 0)
        }
    }

    @Test("moveSlide reorders the slide tree")
    func move() throws {
        var document = try KeynoteDocument(contentsOf: Self.twoSlideURL)
        let before = try document.slideNodeIdentifiers()
        try document.moveSlide(from: 0, to: 1)
        let reread = try writeAndReread(document, as: "op-move.key")
        let after = try reread.slideNodeIdentifiers()
        #expect(after == before.reversed())
    }

    @Test("duplicate then remove returns to a consistent single-slide document")
    func duplicateThenRemove() throws {
        var document = try KeynoteDocument(contentsOf: Self.oneSlideURL)
        try document.duplicateSlide(at: 0)
        try document.removeSlide(at: 1)
        let reread = try writeAndReread(document, as: "op-dup-remove.key")
        #expect(reread.slideCount == 1)
        let text = TextReplacement.allText(in: reread)
        #expect(text.contains { $0.contains("KeynoteKit Fixture") })
    }
}
