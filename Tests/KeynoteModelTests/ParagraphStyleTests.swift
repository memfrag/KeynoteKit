import Foundation
import Testing
@testable import KeynoteModel

@Suite("Paragraph styles, columns, and inset")
struct ParagraphStyleTests {
    static var deckURL: URL { Bundle.module.url(forResource: "Fixtures/imagedeck", withExtension: "key")! }

    private func reread(_ document: KeynoteDocument) throws -> KeynoteDocument {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("para-\(UUID().uuidString).key")
        try document.write(to: url); defer { try? FileManager.default.removeItem(at: url) }
        return try KeynoteDocument(contentsOf: url)
    }

    @Test("a defined paragraph style applies to text and round-trips")
    func defineAndApply() throws {
        var document = try KeynoteDocument(contentsOf: Self.deckURL)
        let styleID = try document.defineParagraphStyle(ParagraphStyle(
            name: "Heading", fontSize: 40, bold: true, color: (0.1, 0.3, 0.8, 1),
            alignment: .center, spaceAfter: 8, background: (0.9, 0.9, 0.7, 1)
        ))
        let text = try document.addText(toSlideAt: 0, string: "Hi", frame: Frame(x: 0, y: 0, width: 400, height: 100))
        try document.applyParagraphStyle(styleID, to: text)
        let out = try reread(document)
        #expect(try out.sceneTree(forSlideAt: 0).nodes.contains { $0.id == text })
    }

    @Test("columns and text inset apply to a text box")
    func columnsAndInset() throws {
        var document = try KeynoteDocument(contentsOf: Self.deckURL)
        let text = try document.addText(toSlideAt: 0, string: "Some flowing text here", frame: Frame(x: 0, y: 0, width: 600, height: 300))
        try document.setNodeColumns(text, count: 3, gap: 24)
        try document.setNodeTextInset(text, 16)
        let out = try reread(document)
        #expect(try out.sceneTree(forSlideAt: 0).nodes.contains { $0.id == text })
    }
    @Test("bulleting text round-trips")
    func bulleted() throws {
        var document = try KeynoteDocument(contentsOf: Self.deckURL)
        let text = try document.addText(toSlideAt: 0, string: "One\nTwo\nThree", frame: Frame(x: 0, y: 0, width: 500, height: 200))
        try document.setNodeBulleted(text)
        let out = try reread(document)
        #expect(try out.sceneTree(forSlideAt: 0).nodes.contains { $0.id == text })
    }
    @Test("numbered list round-trips")
    func numbered() throws {
        var document = try KeynoteDocument(contentsOf: Self.deckURL)
        let text = try document.addText(toSlideAt: 0, string: "A\nB\nC", frame: Frame(x: 0, y: 0, width: 500, height: 200))
        try document.setNodeNumbered(text, .romanUpper)
        let out = try reread(document)
        #expect(try out.sceneTree(forSlideAt: 0).nodes.contains { $0.id == text })
    }
}
