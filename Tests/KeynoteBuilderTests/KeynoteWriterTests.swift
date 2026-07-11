import Foundation
import Testing
@testable import KeynoteBuilder
import KeynoteModel

@Suite("KeynoteWriter (template builder)")
struct KeynoteWriterTests {

    private func buildAndReread(_ presentation: Presentation) throws -> KeynoteDocument {
        let writer = try KeynoteWriter()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("build-\(UUID().uuidString).key")
        try writer.write(presentation, to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try KeynoteDocument(contentsOf: url)
    }

    @Test("builds the requested number of slides")
    func slideCount() throws {
        for count in [1, 2, 5] {
            let slides = (1...count).map { Slide(title: "Slide \($0)") }
            let document = try buildAndReread(Presentation(slides: slides))
            #expect(document.slideCount == count, "expected \(count) slides")
        }
    }

    @Test("sets each slide's title and body")
    func perSlideText() throws {
        let presentation = Presentation {
            Slide(title: "First", body: "Body one")
            Slide(title: "Second", body: "Line A\nLine B")
            Slide(title: "Third")
        }
        let document = try buildAndReread(presentation)
        #expect(try document.slideTitle(at: 0) == "First")
        #expect(try document.slideTitle(at: 1) == "Second")
        #expect(try document.slideTitle(at: 2) == "Third")
        #expect(try document.slideBody(at: 0) == "Body one")
        // Paragraph breaks round-trip as U+2029.
        #expect(try document.slideBody(at: 1) == "Line A\u{2029}Line B")
    }

    @Test("shrinking below the seed's slide count works")
    func singleSlide() throws {
        let document = try buildAndReread(Presentation(slides: [Slide(title: "Only")]))
        #expect(document.slideCount == 1)
        #expect(try document.slideTitle(at: 0) == "Only")
    }

    @Test("an empty presentation is rejected")
    func emptyRejected() throws {
        let writer = try KeynoteWriter()
        #expect(throws: KeynoteWriterError.self) {
            _ = try writer.build(Presentation(slides: []))
        }
    }

    @Test("the result-builder DSL composes slides")
    func dsl() throws {
        let show = true
        let presentation = Presentation {
            Slide(title: "Intro")
            for i in 1...3 {
                Slide(title: "Item \(i)")
            }
            if show {
                Slide(title: "Conditional")
            }
        }
        #expect(presentation.slides.count == 5)
        #expect(presentation.slides.map(\.title) == ["Intro", "Item 1", "Item 2", "Item 3", "Conditional"])
    }
}
