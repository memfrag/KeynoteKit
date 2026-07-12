import Foundation
import Testing
@testable import KeynoteBuilder
import KeynoteModel

@Suite("CanvasWriter (SwiftUI-like DSL)")
struct CanvasWriterTests {

    private var resourceBase: URL {
        // Test resources live next to this file's bundle.
        Bundle.module.resourceURL ?? Bundle.module.bundleURL
    }

    private func buildAndReread(_ canvases: [Canvas]) throws -> KeynoteDocument {
        let writer = try CanvasWriter()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("canvas-\(UUID().uuidString).key")
        try writer.write(canvases, to: url, imageBaseURL: resourceBase)
        defer { try? FileManager.default.removeItem(at: url) }
        return try KeynoteDocument(contentsOf: url)
    }

    private func drawables(_ document: KeynoteDocument, slide: Int = 0) throws -> [SceneNode] {
        try document.sceneTree(forSlideAt: slide).nodes
    }

    @Test("modifiers accumulate on an element")
    func modifiersAccumulate() {
        let element = Text("Hi")
            .frame(x: 10, y: 20, width: 100, height: 40)
            .fontSize(30).bold().italic()
            .foregroundColor(.rgb(0.1, 0.2, 0.3))
        #expect(element.style.frame == Frame(x: 10, y: 20, width: 100, height: 40))
        #expect(element.style.fontSize == 30)
        #expect(element.style.bold == true)
        #expect(element.style.italic == true)
        #expect(element.style.foregroundColor == .rgb(0.1, 0.2, 0.3))
    }

    @Test("an empty canvas list is rejected")
    func emptyRejected() throws {
        let writer = try CanvasWriter()
        #expect(throws: CanvasWriterError.self) {
            _ = try writer.build([])
        }
    }

    @Test("a text element becomes a text node with the given string")
    func textElement() throws {
        let canvas = Canvas {
            Text("Hello canvas").frame(x: 40, y: 40, width: 600, height: 100)
        }
        let document = try buildAndReread([canvas])
        let nodes = try drawables(document)
        let texts = nodes.compactMap(\.text)
        #expect(texts.contains("Hello canvas"))
    }

    @Test("prototypes are removed, leaving only composed elements")
    func prototypesRemoved() throws {
        let canvas = Canvas {
            Text("Only text").frame(x: 40, y: 40, width: 600, height: 100)
        }
        let document = try buildAndReread([canvas])
        let nodes = try drawables(document)
        // No node still carries a prototype label.
        #expect(nodes.allSatisfy { ($0.label ?? "").hasPrefix("kk-proto-") == false })
        // The image and box prototypes are gone; no stray image remains.
        #expect(nodes.contains { $0.type == "image" } == false)
    }

    @Test("a shape element is placed and framed")
    func shapeElement() throws {
        let canvas = Canvas {
            Shape().frame(x: 60, y: 300, width: 360, height: 260).fill(.rgb(0.9, 0.5, 0.1))
        }
        let document = try buildAndReread([canvas])
        let nodes = try drawables(document)
        let shape = nodes.first { $0.type == "shape" && $0.frame?.width == 360 }
        #expect(shape != nil)
        #expect(shape?.frame == Frame(x: 60, y: 300, width: 360, height: 260))
    }

    @Test("an image element materializes and reuses matching data by digest")
    func imageElement() throws {
        let canvas = Canvas {
            // blue.png matches the palette prototype's own image, so this
            // exercises the digest-dedup path that previously collided.
            Image(path: "blue.png").frame(x: 80, y: 200, width: 500, height: 300)
        }
        let document = try buildAndReread([canvas])
        let nodes = try drawables(document)
        #expect(nodes.contains { $0.type == "image" })
        // The document must never carry two datas with the same digest.
        #expect(try document.dataDigestsAreUnique())
    }

    @Test("text, shape, and image compose on one slide")
    func fullComposition() throws {
        let canvas = Canvas {
            Text("Title").frame(x: 60, y: 60, width: 840, height: 120).fontSize(54).bold()
            Shape().frame(x: 60, y: 300, width: 360, height: 260).fill(.rgb(0.9, 0.5, 0.1))
            Image(path: "blue.png").frame(x: 480, y: 300, width: 420, height: 260)
        }
        let document = try buildAndReread([canvas])
        let nodes = try drawables(document)
        #expect(nodes.contains { $0.text == "Title" })
        #expect(nodes.contains { $0.type == "image" })
        #expect(nodes.contains { $0.type == "shape" && $0.frame?.width == 360 })
        #expect(try document.dataDigestsAreUnique())
    }

    @Test("a canvas background is applied without breaking the slide")
    func canvasBackground() throws {
        let canvas = Canvas {
            Text("On a dark slide").frame(x: 40, y: 40, width: 600, height: 100).foregroundColor(.white)
        }
        .background(.color(0.1, 0.2, 0.4, 1))
        let document = try buildAndReread([canvas])
        let nodes = try drawables(document)
        #expect(nodes.contains { $0.text == "On a dark slide" })
        #expect(try document.dataDigestsAreUnique())
    }

    @Test("multiple canvases produce multiple slides")
    func multipleSlides() throws {
        let document = try buildAndReread([
            Canvas { Text("One").frame(x: 40, y: 40, width: 600, height: 100) },
            Canvas { Text("Two").frame(x: 40, y: 40, width: 600, height: 100) },
        ])
        #expect(document.slideCount == 2)
        #expect(try drawables(document, slide: 0).contains { $0.text == "One" })
        #expect(try drawables(document, slide: 1).contains { $0.text == "Two" })
    }
}
