import Foundation
import Testing
@testable import KeynoteModel

@Suite("Per-slide content")
struct SlideContentTests {

    static var twoSlideURL: URL {
        Bundle.module.url(forResource: "Fixtures/twoslides", withExtension: "key")!
    }

    @Test("reads each slide's title independently")
    func readsTitles() throws {
        let document = try KeynoteDocument(contentsOf: Self.twoSlideURL)
        #expect(try document.slideTitle(at: 0) == "First")
        #expect(try document.slideTitle(at: 1) == "Second")
    }

    @Test("sets one slide's title without touching the other")
    func setsTitleIndependently() throws {
        var document = try KeynoteDocument(contentsOf: Self.twoSlideURL)
        try document.setSlideText(at: 0, .title, to: "Rewritten")

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("slide-content.key")
        try document.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let reread = try KeynoteDocument(contentsOf: url)

        #expect(try reread.slideTitle(at: 0) == "Rewritten")
        #expect(try reread.slideTitle(at: 1) == "Second")
    }

    @Test("out-of-range slide index throws")
    func outOfRange() throws {
        var document = try KeynoteDocument(contentsOf: Self.twoSlideURL)
        #expect(throws: SlideContentError.self) {
            try document.setSlideText(at: 9, .title, to: "x")
        }
    }

    @Test("sets and reads presenter notes")
    func notes() throws {
        var document = try KeynoteDocument(contentsOf: Self.twoSlideURL)
        try document.setSlideText(at: 0, .notes, to: "Remember to smile")

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("slide-notes.key")
        try document.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let reread = try KeynoteDocument(contentsOf: url)

        #expect(try reread.slideNotes(at: 0) == "Remember to smile")
        #expect(try reread.slideTitle(at: 0) == "First")
    }
}
