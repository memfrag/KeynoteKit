import Foundation
import Testing
@testable import KeynoteBuilder

@Suite("Markdown presentation parsing")
struct MarkdownPresentationTests {

    @Test("splits slides on --- and reads titles and bodies")
    func basicStructure() {
        let markdown = """
        # First

        Intro paragraph

        ---

        # Second

        - Bullet one
        - Bullet two
        """
        let presentation = Presentation(markdown: markdown)
        #expect(presentation.slides.count == 2)
        #expect(presentation.slides[0].title == "First")
        #expect(presentation.slides[0].body == "Intro paragraph")
        #expect(presentation.slides[1].title == "Second")
        #expect(presentation.slides[1].body == "Bullet one\nBullet two")
    }

    @Test("skips leading YAML front matter")
    func frontMatter() {
        let markdown = """
        ---
        title: Deck
        author: Me
        ---

        # Only slide

        Body
        """
        let presentation = Presentation(markdown: markdown)
        #expect(presentation.slides.count == 1)
        #expect(presentation.slides[0].title == "Only slide")
        #expect(presentation.slides[0].body == "Body")
    }

    @Test("parses Notes: and HTML-comment notes")
    func notes() {
        let markdown = """
        # A

        Body

        Notes: Speaker note line one
        continued line two

        ---

        # B

        <!-- notes: Inline comment note -->
        """
        let presentation = Presentation(markdown: markdown)
        #expect(presentation.slides[0].notes == "Speaker note line one\ncontinued line two")
        #expect(presentation.slides[1].notes == "Inline comment note")
        // Notes text must not leak into the body.
        #expect(presentation.slides[0].body == "Body")
    }

    @Test("collects image references")
    func images() {
        let markdown = """
        # Slide

        ![logo](images/logo.png)

        Some text
        """
        let presentation = Presentation(markdown: markdown)
        #expect(presentation.slides[0].imagePaths == ["images/logo.png"])
        #expect(presentation.slides[0].body == "Some text")
    }

    @Test("places images into the layout's image nodes when building")
    func placesImages() throws {
        let templateURL = try #require(Bundle.module.url(forResource: "template2", withExtension: "key"))
        let blueURL = try #require(Bundle.module.url(forResource: "blue", withExtension: "png"))
        let blue = try Data(contentsOf: blueURL)

        let presentation = Presentation(slides: [
            Slide(title: "Hero", layout: "photo", imagePaths: [blueURL.path]),
        ])
        let writer = try KeynoteWriter(templateURL: templateURL)
        let document = try writer.build(presentation)

        let tree = try document.sceneTree(forSlideAt: 0)
        let largest = try #require(
            tree.nodes.filter { $0.type == "image" }.max {
                ($0.frame?.width ?? 0) * ($0.frame?.height ?? 0) <
                ($1.frame?.width ?? 0) * ($1.frame?.height ?? 0)
            }
        )
        let file = try #require(largest.media?.file)
        #expect(document.dataForEntry(at: "Data/" + file) == blue)
    }

    @Test("any heading level becomes the title; later headings join the body")
    func headings() {
        let markdown = """
        ## Section title

        ### Subheading

        Text
        """
        let presentation = Presentation(markdown: markdown)
        #expect(presentation.slides[0].title == "Section title")
        #expect(presentation.slides[0].body == "Subheading\nText")
    }

    @Test("ignores empty slides")
    func emptySlides() {
        let presentation = Presentation(markdown: "# A\n\n---\n\n\n---\n\n# B")
        #expect(presentation.slides.map(\.title) == ["A", "B"])
    }
}
