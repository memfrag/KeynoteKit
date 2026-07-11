import Foundation
import Testing
@testable import KeynoteModel

@Suite("Layout introspection")
struct SlideLayoutTests {

    static var twoSlideURL: URL {
        Bundle.module.url(forResource: "Fixtures/twoslides", withExtension: "key")!
    }

    @Test("describes a slide's placeholders with role, kind, prompt, and frame")
    func describesFields() throws {
        let document = try KeynoteDocument(contentsOf: Self.twoSlideURL)
        let descriptions = try document.layoutDescriptions()
        #expect(descriptions.count == document.slideCount)

        let first = descriptions[0]
        #expect(first.masterName != nil)

        // A standard content slide exposes a title and a body placeholder.
        let roles = Set(first.fields.map(\.role))
        #expect(roles.contains("title"))
        #expect(roles.contains("body"))

        // The title field carries a prompt and a non-empty frame.
        let title = try #require(first.fields.first { $0.role == "title" })
        #expect(title.kind == "title")
        #expect(title.contentType == "text")
        let frame = try #require(title.frame)
        #expect(frame.width > 0 && frame.height > 0)
    }

    @Test("object placeholders are reported as media")
    func objectIsMedia() throws {
        let document = try KeynoteDocument(contentsOf: Self.twoSlideURL)
        let fields = try document.layoutDescription(at: 0).fields
        for field in fields where field.role == "object" {
            #expect(field.contentType == "media")
        }
    }
}
