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
        // Capture prototype ids once, up front. Only the text prototype is
        // required — shapes and images are synthesized from scratch, so their
        // prototypes are optional (and just deleted if the palette carries
        // them). The text clone inherits the label, so a later lookup would
        // find a clone.
        func prototypeID(_ label: String) throws -> UInt64 {
            let nodes = try document.sceneTree(forSlideAt: index).nodes
            guard let node = nodes.first(where: { $0.label == label }) else {
                throw CanvasWriterError.prototypeMissing(label)
            }
            return node.id
        }
        let textProtoID = try prototypeID(Self.textProto)
        let leftoverProtos = [Self.shapeProto, Self.imageProto].compactMap { try? prototypeID($0) }

        for element in canvas.elements {
            let frame = element.style.frame
            switch element.kind {
            case .text(let string):
                // Text still clones a prototype — a text box's paragraph and
                // character style tables are hard to synthesize from nothing.
                let newID = try document.cloneDrawable(textProtoID, toSlideAt: index)
                try document.setNodeText(newID, to: string)
                if let frame { try document.setNodeFrame(newID, to: frame) }
                try applyStyle(element.style, to: newID, in: &document)
                try? document.setNodeDescription(newID, to: "")
            case .shape:
                let newID = try document.addShape(toSlideAt: index, frame: frame ?? Self.defaultFrame)
                try applyStyle(element.style, to: newID, in: &document)
            case .image(let path):
                let url = URL(fileURLWithPath: path, relativeTo: imageBaseURL)
                try document.addImage(
                    toSlideAt: index,
                    data: try Data(contentsOf: url),
                    frame: frame ?? Self.defaultFrame
                )
            }
        }

        // Remove the prototypes so only the composed elements remain.
        for id in [textProtoID] + leftoverProtos {
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
        if let fill = style.fill {
            try document.setNodeFill(nodeID, to: (fill.red, fill.green, fill.blue, fill.alpha))
        }
    }
}
