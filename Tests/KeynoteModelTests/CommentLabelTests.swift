import Foundation
import Testing
@testable import KeynoteModel

@Suite("Comment labels")
struct CommentLabelTests {

    static var commentsURL: URL {
        Bundle.module.url(forResource: "Fixtures/comments", withExtension: "key")!
    }

    private func writeAndReread(_ document: KeynoteDocument) throws -> KeynoteDocument {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("comment-\(UUID().uuidString).key")
        try document.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try KeynoteDocument(contentsOf: url)
    }

    @Test("reads element comments as scene labels")
    func readsLabels() throws {
        let document = try KeynoteDocument(contentsOf: Self.commentsURL)
        let shapes = try document.sceneTree(forSlideAt: 0).nodes.filter { $0.type == "shape" }
        let labels = Set(shapes.compactMap(\.label))
        #expect(labels.contains("@left"))
        #expect(labels.contains("@right"))
    }

    @Test("fills a shape by its comment label (explicit label beats heuristics)")
    func fillByLabel() throws {
        var document = try KeynoteDocument(contentsOf: Self.commentsURL)
        try document.setSlideText(at: 0, block: "left", to: "Left wins")
        try document.setSlideText(at: 0, block: "@right", to: "Right wins")

        let reread = try writeAndReread(document)
        let shapes = try reread.sceneTree(forSlideAt: 0).nodes.filter { $0.type == "shape" }
        let texts = Set(shapes.compactMap(\.text))
        #expect(texts.contains("Left wins"))
        #expect(texts.contains("Right wins"))
    }

    @Test("stripLabelComments removes @labels but keeps content")
    func strip() throws {
        var document = try KeynoteDocument(contentsOf: Self.commentsURL)
        try document.setSlideText(at: 0, block: "left", to: "Kept text")
        try document.stripLabelComments()

        let reread = try writeAndReread(document)
        let shapes = try reread.sceneTree(forSlideAt: 0).nodes.filter { $0.type == "shape" }
        // No @labels remain…
        #expect(shapes.allSatisfy { !($0.label?.hasPrefix("@") ?? false) })
        // …and the filled content survives.
        #expect(shapes.contains { $0.text == "Kept text" })
    }
}
