import Foundation

/// A presentation described declaratively, independent of the Keynote file
/// format. `KeynoteWriter` maps it onto a template document to produce a
/// `.key` file.
public struct Presentation {
    public var slides: [Slide]

    public init(slides: [Slide] = []) {
        self.slides = slides
    }

    public init(@SlideBuilder _ content: () -> [Slide]) {
        self.slides = content()
    }
}

/// One slide's editable content. `nil` leaves the template placeholder's
/// existing text in place; an empty string clears it.
public struct Slide {
    public var title: String?
    public var body: String?
    /// Presenter notes.
    public var notes: String?
    /// Names the template layout to use, matched against a template deck's
    /// `@layout:` tags or master-slide names (see `TemplateLibrary`). `nil`
    /// lets the writer pick a default. Ignored when building without a
    /// multi-layout template.
    public var layout: String?
    /// Image file paths parsed from the source (e.g. markdown `![](…)`).
    /// Not yet rendered — image placement lands with M4; carried so the
    /// format stays forward-compatible.
    public var imagePaths: [String]

    public init(
        title: String? = nil,
        body: String? = nil,
        notes: String? = nil,
        layout: String? = nil,
        imagePaths: [String] = []
    ) {
        self.title = title
        self.body = body
        self.notes = notes
        self.layout = layout
        self.imagePaths = imagePaths
    }
}

@resultBuilder
public enum SlideBuilder {
    public static func buildExpression(_ slide: Slide) -> [Slide] { [slide] }
    public static func buildExpression(_ slides: [Slide]) -> [Slide] { slides }
    public static func buildBlock(_ groups: [Slide]...) -> [Slide] { groups.flatMap { $0 } }
    public static func buildArray(_ groups: [[Slide]]) -> [Slide] { groups.flatMap { $0 } }
    public static func buildOptional(_ slides: [Slide]?) -> [Slide] { slides ?? [] }
    public static func buildEither(first slides: [Slide]) -> [Slide] { slides }
    public static func buildEither(second slides: [Slide]) -> [Slide] { slides }
}
