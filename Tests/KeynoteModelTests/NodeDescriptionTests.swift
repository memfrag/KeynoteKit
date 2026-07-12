import Foundation
import Testing
@testable import KeynoteModel

@Suite("Node descriptions (labels)")
struct NodeDescriptionTests {

    static var imageDeckURL: URL {
        Bundle.module.url(forResource: "Fixtures/imagedeck", withExtension: "key")!
    }

    static var blueImageURL: URL {
        Bundle.module.url(forResource: "Fixtures/blue", withExtension: "png")!
    }

    private func writeAndReread(_ document: KeynoteDocument) throws -> KeynoteDocument {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("desc-\(UUID().uuidString).key")
        try document.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try KeynoteDocument(contentsOf: url)
    }

    @Test("sets and reads a node's description, surfaced as the scene label")
    func roundTrip() throws {
        var document = try KeynoteDocument(contentsOf: Self.imageDeckURL)
        let image = try #require(
            try document.sceneTree(forSlideAt: 0).nodes.first { $0.type == "image" }
        )
        try document.setNodeDescription(image.id, to: "@hero")

        let reread = try writeAndReread(document)
        #expect(try reread.nodeDescription(image.id) == "@hero")
        let node = try #require(try reread.sceneTree(forSlideAt: 0).nodes.first { $0.id == image.id })
        #expect(node.label == "@hero")
    }

    @Test("places an image by its description label")
    func imageByLabel() throws {
        var document = try KeynoteDocument(contentsOf: Self.imageDeckURL)
        let image = try #require(
            try document.sceneTree(forSlideAt: 0).nodes.first { $0.type == "image" }
        )
        try document.setNodeDescription(image.id, to: "@hero")

        // The "@" is optional in the key.
        let blue = try Data(contentsOf: Self.blueImageURL)
        try document.setSlideImage(at: 0, matching: "hero", to: blue)

        let reread = try writeAndReread(document)
        let node = try #require(try reread.sceneTree(forSlideAt: 0).nodes.first { $0.id == image.id })
        let file = try #require(node.media?.file)
        #expect(reread.dataForEntry(at: "Data/" + file) == blue)
    }

    @Test("an unmatched image label throws")
    func noMatch() throws {
        var document = try KeynoteDocument(contentsOf: Self.imageDeckURL)
        #expect(throws: (any Error).self) {
            try document.setSlideImage(at: 0, matching: "nonexistent", to: Data([1, 2, 3]))
        }
    }
}
