import Foundation
import Testing
@testable import KeynoteModel

@Suite("Names and comments")
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

    @Test("comments are read as intent, separate from the label")
    func commentsAreIntent() throws {
        let document = try KeynoteDocument(contentsOf: Self.commentsURL)
        let shapes = try document.sceneTree(forSlideAt: 0).nodes.filter { $0.type == "shape" }
        // The fixture's shapes carry comments; they surface as `comment`.
        let comments = Set(shapes.compactMap(\.comment))
        #expect(comments.contains("@left"))
        #expect(comments.contains("@right"))
        // …and a comment is NOT used as the addressing label.
        #expect(shapes.allSatisfy { $0.label != "@left" && $0.label != "@right" })
    }

    @Test("an element's Object List name is its label")
    func nameIsLabel() throws {
        var document = try KeynoteDocument(contentsOf: Self.commentsURL)
        let shapes = try document.sceneTree(forSlideAt: 0).nodes.filter { $0.type == "shape" }
        let target = try #require(shapes.first)
        try document.setNodeName(target.id, to: "hero")

        let reread = try writeAndReread(document)
        let named = try reread.sceneTree(forSlideAt: 0).nodes.first { $0.id == target.id }
        #expect(named?.label == "hero")
        #expect(try reread.nodeName(target.id) == "hero")
    }

    @Test("setSlideText fills a block by its name")
    func fillByName() throws {
        var document = try KeynoteDocument(contentsOf: Self.commentsURL)
        let shapes = try document.sceneTree(forSlideAt: 0).nodes.filter { $0.type == "shape" }
        let target = try #require(shapes.first)
        try document.setNodeName(target.id, to: "callout")

        let reread0 = try writeAndReread(document)
        var doc = reread0
        try doc.setSlideText(at: 0, block: "callout", to: "Named content")

        let reread = try writeAndReread(doc)
        #expect(try reread.sceneTree(forSlideAt: 0).nodes.contains { $0.text == "Named content" })
    }
}
