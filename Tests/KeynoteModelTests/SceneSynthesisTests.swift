import Foundation
import Testing
@testable import KeynoteModel

@Suite("Scene synthesis (from-scratch drawables)")
struct SceneSynthesisTests {

    static var deckURL: URL {
        Bundle.module.url(forResource: "Fixtures/imagedeck", withExtension: "key")!
    }
    static var blueImageURL: URL {
        Bundle.module.url(forResource: "Fixtures/blue", withExtension: "png")!
    }

    private func writeAndReread(_ document: KeynoteDocument) throws -> KeynoteDocument {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("synth-\(UUID().uuidString).key")
        try document.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try KeynoteDocument(contentsOf: url)
    }

    @Test("addShape places a new shape node with the given frame")
    func addShape() throws {
        var document = try KeynoteDocument(contentsOf: Self.deckURL)
        let before = try document.sceneTree(forSlideAt: 0).nodes.count
        let id = try document.addShape(toSlideAt: 0, frame: Frame(x: 100, y: 120, width: 400, height: 260))

        let reread = try writeAndReread(document)
        let nodes = try reread.sceneTree(forSlideAt: 0).nodes
        #expect(nodes.count == before + 1)
        let shape = nodes.first { $0.id == id }
        #expect(shape?.type == "shape")
        #expect(shape?.frame == Frame(x: 100, y: 120, width: 400, height: 260))
    }

    @Test("a synthesized shape can be filled")
    func fillSynthesizedShape() throws {
        var document = try KeynoteDocument(contentsOf: Self.deckURL)
        let id = try document.addShape(toSlideAt: 0, frame: Frame(x: 0, y: 0, width: 200, height: 200))
        // Applying a fill to a from-scratch shape must not throw — it makes a
        // variation of the theme shape style the synthesized shape references.
        try document.setNodeFill(id, to: (0.2, 0.7, 0.4, 1))
        let reread = try writeAndReread(document)
        #expect(try reread.sceneTree(forSlideAt: 0).nodes.contains { $0.id == id })
    }

    @Test("addText places a text node with the given string and frame")
    func addText() throws {
        var document = try KeynoteDocument(contentsOf: Self.deckURL)
        let id = try document.addText(toSlideAt: 0, string: "Hello", frame: Frame(x: 40, y: 40, width: 600, height: 100))
        let reread = try writeAndReread(document)
        let node = try reread.sceneTree(forSlideAt: 0).nodes.first { $0.id == id }
        #expect(node?.text == "Hello")
        #expect(node?.frame == Frame(x: 40, y: 40, width: 600, height: 100))
    }

    @Test("multi-paragraph synthesized text round-trips paragraph breaks")
    func addMultilineText() throws {
        var document = try KeynoteDocument(contentsOf: Self.deckURL)
        let id = try document.addText(toSlideAt: 0, string: "Line A\nLine B", frame: Frame(x: 0, y: 0, width: 400, height: 200))
        let reread = try writeAndReread(document)
        let node = try reread.sceneTree(forSlideAt: 0).nodes.first { $0.id == id }
        #expect(node?.text == "Line A\u{2029}Line B")
    }

    @Test("synthesized text accepts character-style overrides")
    func styleSynthesizedText() throws {
        var document = try KeynoteDocument(contentsOf: Self.deckURL)
        let id = try document.addText(toSlideAt: 0, string: "Styled", frame: Frame(x: 0, y: 0, width: 400, height: 100))
        // A from-scratch text box must carry a base character style to vary.
        try document.setNodeCharacterStyle(id, fontSize: 40, bold: true, color: (0.1, 0.3, 0.8, 1))
        let reread = try writeAndReread(document)
        #expect(try reread.sceneTree(forSlideAt: 0).nodes.contains { $0.id == id })
    }

    @Test("setSlideBackground applies without breaking the document")
    func setBackground() throws {
        var document = try KeynoteDocument(contentsOf: Self.deckURL)
        try document.setSlideBackground(at: 0, to: (0.1, 0.2, 0.4, 1))
        let reread = try writeAndReread(document)
        // The slide still reads back with its nodes intact.
        #expect(try reread.sceneTree(forSlideAt: 0).nodes.isEmpty == false)
    }

    @Test("every background fill kind round-trips")
    func backgroundFillKinds() throws {
        let sun = try Data(contentsOf: Self.blueImageURL)
        let fills: [Fill] = [
            .none,
            .color(0.2, 0.3, 0.5, 1),
            .linearGradient(stops: [
                GradientStop(color: (0, 0, 0, 1), location: 0),
                GradientStop(color: (1, 1, 1, 1), location: 1),
            ], angleDegrees: 45),
            .radialGradient(stops: [
                GradientStop(color: (1, 1, 0, 1), location: 0),
                GradientStop(color: (1, 0, 0, 1), location: 1),
            ]),
            .image(sun, mode: .scaleToFill),
        ]
        for fill in fills {
            var document = try KeynoteDocument(contentsOf: Self.deckURL)
            try document.setSlideBackground(at: 0, fill: fill)
            let reread = try writeAndReread(document)
            #expect(try reread.dataDigestsAreUnique())
            #expect(try reread.sceneTree(forSlideAt: 0).nodes.isEmpty == false)
        }
    }

    @Test("border and shadow apply to shape, text, and image")
    func borderAndShadow() throws {
        let border = Border(color: (1, 1, 1, 1), width: 4)
        let shadow = Shadow(offset: 6, blur: 8, opacity: 0.6)

        var document = try KeynoteDocument(contentsOf: Self.deckURL)
        let shapeID = try document.addShape(toSlideAt: 0, frame: Frame(x: 0, y: 0, width: 200, height: 150))
        try document.setNodeStyle(shapeID, fill: .color(0.9, 0.5, 0.1, 1), border: border, shadow: shadow)

        let textID = try document.addText(toSlideAt: 0, string: "Framed", frame: Frame(x: 220, y: 0, width: 300, height: 100))
        try document.setNodeStyle(textID, border: border, shadow: shadow)

        let imageID = try document.addImage(
            toSlideAt: 0, data: try Data(contentsOf: Self.blueImageURL),
            frame: Frame(x: 0, y: 200, width: 200, height: 150)
        )
        try document.setNodeStyle(imageID, border: border, shadow: shadow)

        let reread = try writeAndReread(document)
        let ids = Set(try reread.sceneTree(forSlideAt: 0).nodes.map(\.id))
        #expect(ids.isSuperset(of: [shapeID, textID, imageID]))
        #expect(try reread.dataDigestsAreUnique())
    }

    @Test("a synthesized shape accepts gradient and image fills")
    func shapeFillKinds() throws {
        let sun = try Data(contentsOf: Self.blueImageURL)
        let fills: [Fill] = [
            .color(0.9, 0.5, 0.1, 1),
            .linearGradient(stops: [
                GradientStop(color: (1, 0, 0, 1), location: 0),
                GradientStop(color: (0, 0, 1, 1), location: 1),
            ], angleDegrees: 90),
            .radialGradient(stops: [
                GradientStop(color: (1, 1, 1, 1), location: 0),
                GradientStop(color: (0, 0, 0, 1), location: 1),
            ]),
            .image(sun, mode: .tile),
        ]
        for fill in fills {
            var document = try KeynoteDocument(contentsOf: Self.deckURL)
            let id = try document.addShape(toSlideAt: 0, frame: Frame(x: 0, y: 0, width: 300, height: 200))
            try document.setNodeFill(id, fill: fill)
            let reread = try writeAndReread(document)
            #expect(try reread.dataDigestsAreUnique())
            #expect(try reread.sceneTree(forSlideAt: 0).nodes.contains { $0.id == id })
        }
    }

    @Test("addImage registers data and places an image node")
    func addImage() throws {
        var document = try KeynoteDocument(contentsOf: Self.deckURL)
        let data = try Data(contentsOf: Self.blueImageURL)
        let id = try document.addImage(toSlideAt: 0, data: data, frame: Frame(x: 60, y: 60, width: 300, height: 200))

        let reread = try writeAndReread(document)
        let nodes = try reread.sceneTree(forSlideAt: 0).nodes
        let image = nodes.first { $0.id == id }
        #expect(image?.type == "image")
        #expect(image?.frame == Frame(x: 60, y: 60, width: 300, height: 200))
        #expect(try reread.dataDigestsAreUnique())
    }

    @Test("adding the same image twice keeps digests unique")
    func addImageTwiceDedups() throws {
        var document = try KeynoteDocument(contentsOf: Self.deckURL)
        let data = try Data(contentsOf: Self.blueImageURL)
        _ = try document.addImage(toSlideAt: 0, data: data, frame: Frame(x: 0, y: 0, width: 200, height: 200))
        _ = try document.addImage(toSlideAt: 0, data: data, frame: Frame(x: 300, y: 0, width: 200, height: 200))
        let reread = try writeAndReread(document)
        #expect(try reread.dataDigestsAreUnique())
    }
}
