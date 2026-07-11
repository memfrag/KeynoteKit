import Foundation
import Testing
@testable import KeynoteModel

@Suite("Slide text blocks")
struct SlideTextBlockTests {

    static var twoColURL: URL {
        Bundle.module.url(forResource: "Fixtures/twocol", withExtension: "key")!
    }

    private func writeAndReread(_ document: KeynoteDocument) throws -> KeynoteDocument {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("blocks-\(UUID().uuidString).key")
        try document.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try KeynoteDocument(contentsOf: url)
    }

    @Test("lists every text block with its addressing keys")
    func lists() throws {
        let document = try KeynoteDocument(contentsOf: Self.twoColURL)
        let blocks = try document.slideTextBlocks(at: 0)
        // The Blank master's title + body + slideNumber, plus three labeled
        // text boxes.
        #expect(blocks.contains { $0.role == "title" })
        #expect(blocks.contains { $0.text == "left" })
        #expect(blocks.contains { $0.text == "right" })
        #expect(blocks.contains { $0.text == "header" })
    }

    @Test("sets a block by its label")
    func setByLabel() throws {
        var document = try KeynoteDocument(contentsOf: Self.twoColURL)
        try document.setSlideText(at: 0, block: "left", to: "A\nB\nC")
        try document.setSlideText(at: 0, block: "right", to: "X\nY")

        let reread = try writeAndReread(document)
        let blocks = try reread.slideTextBlocks(at: 0)
        #expect(blocks.contains { $0.text == "A\u{2029}B\u{2029}C" })
        #expect(blocks.contains { $0.text == "X\u{2029}Y" })
        // Untouched blocks keep their labels.
        #expect(blocks.contains { $0.text == "header" })
    }

    @Test("sets a block by role")
    func setByRole() throws {
        var document = try KeynoteDocument(contentsOf: Self.twoColURL)
        try document.setSlideText(at: 0, block: "title", to: "The Title")
        #expect(try document.slideTitle(at: 0) == "The Title")
    }

    @Test("an unknown block key throws")
    func unknown() throws {
        var document = try KeynoteDocument(contentsOf: Self.twoColURL)
        #expect(throws: TextBlockError.self) {
            try document.setSlideText(at: 0, block: "nonexistent-block", to: "x")
        }
    }
}
