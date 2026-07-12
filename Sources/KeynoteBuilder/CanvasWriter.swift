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
        // Capture the original prototype ids once — clones inherit the label,
        // so re-looking-up would find a clone after the first element.
        func prototypeID(_ label: String) throws -> UInt64 {
            let nodes = try document.sceneTree(forSlideAt: index).nodes
            guard let node = nodes.first(where: { $0.label == label }) else {
                throw CanvasWriterError.prototypeMissing(label)
            }
            return node.id
        }
        let textProtoID = try prototypeID(Self.textProto)
        let shapeProtoID = try prototypeID(Self.shapeProto)
        let imageProtoID = try prototypeID(Self.imageProto)

        for element in canvas.elements {
            let sourceID: UInt64
            switch element.kind {
            case .text: sourceID = textProtoID
            case .shape: sourceID = shapeProtoID
            case .image: sourceID = imageProtoID
            }
            let newID = try document.cloneDrawable(sourceID, toSlideAt: index)

            switch element.kind {
            case .text(let string):
                try document.setNodeText(newID, to: string)
            case .image(let path):
                let url = URL(fileURLWithPath: path, relativeTo: imageBaseURL)
                try document.setNodeMedia(newID, to: try Data(contentsOf: url))
            case .shape:
                break
            }
            if let frame = element.style.frame {
                try document.setNodeFrame(newID, to: frame)
            }
            try applyStyle(element.style, to: newID, in: &document)
            // Clear the label the clone inherited from its prototype.
            try? document.setNodeDescription(newID, to: "")
        }

        // Remove the prototypes so only the composed elements remain.
        for id in [textProtoID, shapeProtoID, imageProtoID] {
            try? document.deleteDrawable(id)
        }
    }

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
