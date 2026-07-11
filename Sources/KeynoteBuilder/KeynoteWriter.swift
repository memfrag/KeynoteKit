import Foundation
import KeynoteModel

public enum KeynoteWriterError: Error {
    case seedResourceMissing
    case emptyPresentation
}

/// Produces a `.key` file from a `Presentation` using the template strategy:
/// start from a seed document (one title+body slide), grow or shrink it to
/// the requested slide count by duplicating/removing slide 0, then set each
/// slide's title and body text.
///
/// The seed carries a real Keynote theme, master slides, and stylesheets, so
/// the output inherits genuine Keynote styling rather than anything
/// synthesized. Pass a custom `templateURL` to start from your own `.key`
/// (e.g. a branded theme) instead of the bundled seed.
public struct KeynoteWriter {
    private let templateURL: URL

    public init(templateURL: URL? = nil) throws {
        if let templateURL {
            self.templateURL = templateURL
        } else {
            guard let bundled = Bundle.module.url(forResource: "seed", withExtension: "key") else {
                throw KeynoteWriterError.seedResourceMissing
            }
            self.templateURL = bundled
        }
    }

    /// Builds `presentation` and writes the resulting `.key` to `url`.
    public func write(_ presentation: Presentation, to url: URL) throws {
        let document = try build(presentation)
        try document.write(to: url)
    }

    /// Builds `presentation` into a `KeynoteDocument` for further mutation
    /// (e.g. image replacement) before writing.
    public func build(_ presentation: Presentation) throws -> KeynoteDocument {
        guard !presentation.slides.isEmpty else {
            throw KeynoteWriterError.emptyPresentation
        }
        var document = try KeynoteDocument(contentsOf: templateURL)

        // Grow/shrink the deck to match the requested slide count by cloning
        // or removing the first slide. New slides are inserted after index 0,
        // so cloning `target - 1` times yields `target` slides.
        let target = presentation.slides.count
        var current = document.slideCount
        while current < target {
            try document.duplicateSlide(at: 0)
            current += 1
        }
        while current > target {
            try document.removeSlide(at: current - 1)
            current -= 1
        }

        for (index, slide) in presentation.slides.enumerated() {
            if let title = slide.title {
                try document.setSlideText(at: index, .title, to: title)
            }
            if let body = slide.body {
                try document.setSlideText(at: index, .body, to: body)
            }
            if let notes = slide.notes {
                try document.setSlideText(at: index, .notes, to: notes)
            }
        }
        return document
    }
}
