import Foundation
import KeynoteModel

public enum CanvasWriterError: Error {
    case paletteMissing
    case prototypeMissing(String)
    case emptyCanvas
}

/// Renders free-form ``Canvas`` slides — elements placed by absolute position
/// with a SwiftUI-like syntax — into a `.key`.
///
/// Each element is realized by cloning a prototype from a bundled palette
/// (a text box, an image, a shape), so it inherits valid Keynote structure
/// and default styling; the element's content and position are then applied.
public struct CanvasWriter {
    private let paletteURL: URL

    private static let textProto = "kk-proto-text"
    private static let shapeProto = "kk-proto-box"
    private static let imageProto = "kk-proto-image"

    public init(paletteURL: URL? = nil) throws {
        if let paletteURL {
            self.paletteURL = paletteURL
        } else {
            guard let bundled = Bundle.module.url(forResource: "palette", withExtension: "key") else {
                throw CanvasWriterError.paletteMissing
            }
            self.paletteURL = bundled
        }
    }

    public func write(_ canvases: [Canvas], to url: URL, imageBaseURL: URL? = nil) throws {
        let document = try build(canvases, imageBaseURL: imageBaseURL)
        try document.write(to: url)
    }

    public func build(_ canvases: [Canvas], imageBaseURL: URL? = nil) throws -> KeynoteDocument {
        guard !canvases.isEmpty else { throw CanvasWriterError.emptyCanvas }
        var document = try KeynoteDocument(contentsOf: paletteURL)

        while document.slideCount < canvases.count { try document.duplicateSlide(at: 0) }
        while document.slideCount > canvases.count { try document.removeSlide(at: document.slideCount - 1) }

        for (index, canvas) in canvases.enumerated() {
            try render(canvas, at: index, in: &document, imageBaseURL: imageBaseURL)
        }
        return document
    }

    private func render(
        _ canvas: Canvas, at index: Int,
        in document: inout KeynoteDocument, imageBaseURL: URL?
    ) throws {
        // Every element is synthesized from scratch — nothing is cloned — so
        // the seed's prototypes are only removed, never used. Capture them up
        // front (they may be absent in a slimmed seed).
        func prototypeID(_ label: String) -> UInt64? {
            let nodes = (try? document.sceneTree(forSlideAt: index).nodes) ?? []
            return nodes.first(where: { $0.label == label })?.id
        }
        let leftoverProtos = [Self.textProto, Self.shapeProto, Self.imageProto].compactMap(prototypeID)

        if let background = canvas.background {
            try document.setSlideBackground(at: index, fill: background)
        }

        for element in canvas.elements {
            let frame = element.style.frame ?? Self.defaultFrame
            switch element.kind {
            case .text(let string):
                let newID = try document.addText(toSlideAt: index, string: string, frame: frame)
                try applyStyle(element.style, to: newID, in: &document)
            case .shape(let kind):
                let newID = try document.addShape(toSlideAt: index, frame: frame, kind: kind)
                try applyStyle(element.style, to: newID, in: &document)
            case .image(let path):
                let url = URL(fileURLWithPath: path, relativeTo: imageBaseURL)
                let newID = try document.addImage(toSlideAt: index, data: try Data(contentsOf: url), frame: frame)
                try applyStyle(element.style, to: newID, in: &document)
            }
        }

        // Remove the seed's prototypes so only the composed elements remain.
        for id in leftoverProtos {
            try? document.deleteDrawable(id)
        }
    }

    private static let defaultFrame = Frame(x: 0, y: 0, width: 300, height: 200)

    private func applyStyle(_ style: ElementStyle, to nodeID: UInt64, in document: inout KeynoteDocument) throws {
        if style.fontSize != nil || style.bold != nil || style.italic != nil || style.foregroundColor != nil {
            try document.setNodeCharacterStyle(
                nodeID,
                fontSize: style.fontSize,
                bold: style.bold,
                italic: style.italic,
                color: style.foregroundColor.map { ($0.red, $0.green, $0.blue, $0.alpha) }
            )
        }
        try document.setNodeStyle(
            nodeID, fill: style.fill, border: style.border, shadow: style.shadow,
            opacity: style.opacity, startCap: style.startCap, endCap: style.endCap
        )
        if let rotation = style.rotationDegrees {
            try document.setNodeRotation(nodeID, degrees: rotation)
        }
    }
}
