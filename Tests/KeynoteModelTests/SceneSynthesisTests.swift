import Foundation
import Testing
@testable import KeynoteModel

@Suite("Scene synthesis (from-scratch drawables)")
struct SceneSynthesisTests {

    static var deckURL: URL {
        Bundle.module.url(forResource: "Fixtures/imagedeck", withExtension: "key")!
    }
    static var blueImageURL: URL {
        Bundle.module.url(forResource: "Fixtures/blue", withExtension: "png")!
    }

    private func writeAndReread(_ document: KeynoteDocument) throws -> KeynoteDocument {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("synth-\(UUID().uuidString).key")
        try document.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try KeynoteDocument(contentsOf: url)
    }

    @Test("addShape places a new shape node with the given frame")
    func addShape() throws {
        var document = try KeynoteDocument(contentsOf: Self.deckURL)
        let before = try document.sceneTree(forSlideAt: 0).nodes.count
        let id = try document.addShape(toSlideAt: 0, frame: Frame(x: 100, y: 120, width: 400, height: 260))

        let reread = try writeAndReread(document)
        let nodes = try reread.sceneTree(forSlideAt: 0).nodes
        #expect(nodes.count == before + 1)
        let shape = nodes.first { $0.id == id }
        #expect(shape?.type == "shape")
        #expect(shape?.frame == Frame(x: 100, y: 120, width: 400, height: 260))
    }

    @Test("a synthesized shape can be filled")
    func fillSynthesizedShape() throws {
        var document = try KeynoteDocument(contentsOf: Self.deckURL)
        let id = try document.addShape(toSlideAt: 0, frame: Frame(x: 0, y: 0, width: 200, height: 200))
        // Applying a fill to a from-scratch shape must not throw — it makes a
        // variation of the theme shape style the synthesized shape references.
        try document.setNodeFill(id, to: (0.2, 0.7, 0.4, 1))
        let reread = try writeAndReread(document)
        #expect(try reread.sceneTree(forSlideAt: 0).nodes.contains { $0.id == id })
    }

    @Test("addImage registers data and places an image node")
    func addImage() throws {
        var document = try KeynoteDocument(contentsOf: Self.deckURL)
        let data = try Data(contentsOf: Self.blueImageURL)
        let id = try document.addImage(toSlideAt: 0, data: data, frame: Frame(x: 60, y: 60, width: 300, height: 200))

        let reread = try writeAndReread(document)
        let nodes = try reread.sceneTree(forSlideAt: 0).nodes
        let image = nodes.first { $0.id == id }
        #expect(image?.type == "image")
        #expect(image?.frame == Frame(x: 60, y: 60, width: 300, height: 200))
        #expect(try reread.dataDigestsAreUnique())
    }

    @Test("adding the same image twice keeps digests unique")
    func addImageTwiceDedups() throws {
        var document = try KeynoteDocument(contentsOf: Self.deckURL)
        let data = try Data(contentsOf: Self.blueImageURL)
        _ = try document.addImage(toSlideAt: 0, data: data, frame: Frame(x: 0, y: 0, width: 200, height: 200))
        _ = try document.addImage(toSlideAt: 0, data: data, frame: Frame(x: 300, y: 0, width: 200, height: 200))
        let reread = try writeAndReread(document)
        #expect(try reread.dataDigestsAreUnique())
    }
}
