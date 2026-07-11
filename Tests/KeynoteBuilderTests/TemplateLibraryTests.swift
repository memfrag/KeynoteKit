import Foundation
import Testing
@testable import KeynoteBuilder
import KeynoteModel

@Suite("Template library and layout selection")
struct TemplateLibraryTests {

    static var templateURL: URL {
        Bundle.module.url(forResource: "template", withExtension: "key")!
    }

    @Test("indexes template slides by their @layout: notes tag")
    func indexesByTag() throws {
        let library = try TemplateLibrary(templateURL: Self.templateURL)
        #expect(library.declaresLayouts)
        for tag in ["title", "bullets", "section", "statement", "quote"] {
            #expect(library.slideIndex(for: tag) != nil, "missing layout \(tag)")
        }
    }

    @Test("also resolves by master (slide layout) name")
    func indexesByMasterName() throws {
        let library = try TemplateLibrary(templateURL: Self.templateURL)
        // The bullets example is built on the "Title & Bullets" master.
        #expect(library.slideIndex(for: "Title & Bullets") != nil)
        #expect(library.slideIndex(for: "Section") != nil)
    }

    @Test("builds a deck that uses the requested master per slide")
    func buildsWithLayouts() throws {
        let presentation = Presentation {
            Slide(title: "Opening", layout: "title")
            Slide(title: "Divider", layout: "section")
            Slide(title: "Content", body: "First point\nSecond point", layout: "bullets")
            Slide(title: "The punchline", layout: "statement")
        }
        let writer = try KeynoteWriter(templateURL: Self.templateURL)
        let document = try writer.build(presentation)

        #expect(document.slideCount == 4)
        #expect(try document.slideMasterName(at: 0) == "Title")
        #expect(try document.slideMasterName(at: 1) == "Section")
        #expect(try document.slideMasterName(at: 2) == "Title & Bullets")
        #expect(try document.slideMasterName(at: 3) == "Statement")

        // Title-primary layouts keep the title; body-primary (statement)
        // routes the text into the body.
        #expect(try document.slideTitle(at: 0) == "Opening")
        #expect(try document.slideBody(at: 2) == "First point\u{2029}Second point")
        #expect(try document.slideBody(at: 3) == "The punchline")

        // The template's example slides are gone; only content remains.
        for index in 0..<document.slideCount {
            let notes = try document.slideNotes(at: index)
            #expect(!(notes?.contains("@layout") ?? false), "layout tag leaked into slide \(index) notes")
        }
    }

    @Test("an unknown layout is reported with the available ones")
    func unknownLayout() throws {
        let writer = try KeynoteWriter(templateURL: Self.templateURL)
        let presentation = Presentation(slides: [Slide(title: "x", layout: "does-not-exist")])
        #expect {
            _ = try writer.build(presentation)
        } throws: { error in
            guard case KeynoteWriterError.unknownLayout(let requested, let available) = error else { return false }
            return requested == "does-not-exist" && available.contains("statement")
        }
    }

    @Test("fills arbitrary text blocks by label")
    func textBlocks() throws {
        let templateURL = try #require(Bundle.module.url(forResource: "twocol", withExtension: "key"))
        let presentation = Presentation {
            Slide(layout: "two-column", blocks: [
                "header": "Build vs. Buy",
                "left": "Full control\nOwn the roadmap",
                "right": "Faster to ship\nVendor lock-in",
            ])
        }
        let writer = try KeynoteWriter(templateURL: templateURL)
        let document = try writer.build(presentation)

        let blocks = try document.slideTextBlocks(at: 0)
        #expect(blocks.contains { $0.text == "Build vs. Buy" })
        #expect(blocks.contains { $0.text == "Full control\u{2029}Own the roadmap" })
        #expect(blocks.contains { $0.text == "Faster to ship\u{2029}Vendor lock-in" })
    }

    @Test("slides without a layout use the default")
    func defaultLayout() throws {
        var writer = try KeynoteWriter(templateURL: Self.templateURL)
        writer.defaultLayout = "section"
        let document = try writer.build(Presentation(slides: [Slide(title: "No layout named")]))
        #expect(try document.slideMasterName(at: 0) == "Section")
    }
}
