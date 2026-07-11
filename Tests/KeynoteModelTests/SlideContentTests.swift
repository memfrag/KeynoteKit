import Foundation
import Testing
@testable import KeynoteModel
import KeynoteSchemas

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

    @Test("multi-paragraph text replicates paragraph style tables per paragraph")
    func paragraphTables() throws {
        var document = try KeynoteDocument(contentsOf: Self.twoSlideURL)
        try document.setSlideText(at: 0, .body, to: "One\nTwo\nThree")

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("para-tables.key")
        try document.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let reread = try KeynoteDocument(contentsOf: url)
        #expect(try reread.slideBody(at: 0) == "One\u{2029}Two\u{2029}Three")

        // Inspect the storage: paragraph-keyed tables must have one entry
        // per paragraph, at the right UTF-16 offsets (0, 4, 8).
        let storages = reread.components.flatMap(\.records).compactMap { record -> TSWP_StorageArchive? in
            guard record.primaryType == 2001,
                  let s = try? record.decode(TSWP_StorageArchive.self),
                  s.text.first == "One\u{2029}Two\u{2029}Three" else { return nil }
            return s
        }
        let storage = try #require(storages.first)
        #expect(storage.tableParaStyle.entries.map(\.characterIndex) == [0, 4, 8])
        #expect(storage.tableParaStarts.entries.map(\.characterIndex) == [0, 4, 8])
        #expect(storage.tableListStyle.entries.map(\.characterIndex) == [0, 4, 8])
        // All paragraphs share the first paragraph's style object.
        let styleIDs = Set(storage.tableParaStyle.entries.map(\.object.identifier))
        #expect(styleIDs.count == 1)
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
