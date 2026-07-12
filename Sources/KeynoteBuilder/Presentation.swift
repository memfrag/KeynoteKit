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
    /// Additional text blocks for layouts with more than a title and body —
    /// two-column bullets, a subtitle, a quote's attribution, and so on.
    ///
    /// Each key addresses a text region on the template slide, matched
    /// against the region's role (`"title"`, `"body"`, `"object"`), the label
    /// the template author typed into it (`"left"`, `"right"`), or the
    /// layout's prompt (`"Attribution"`). List a template's blocks with
    /// `iwatool blocks-of template.key <slide>` or
    /// `KeynoteDocument.slideTextBlocks(at:)`. Values use `\n` for
    /// bullet/paragraph breaks. Applied after `title`/`body`.
    public var blocks: [String: String]
    /// Names the template layout to use, matched against a template deck's
    /// `@layout:` tags or master-slide names (see `TemplateLibrary`). `nil`
    /// lets the writer pick a default. Ignored when building without a
    /// multi-layout template.
    public var layout: String?
    /// Image file paths placed into the layout's image nodes, largest frame
    /// first. Use `images` instead to target specific images by label.
    public var imagePaths: [String]
    /// Images addressed by label: each key is an image's description (set in
    /// Keynote's inspector, e.g. `@hero`), the value is the file path. This
    /// removes the ambiguity of `imagePaths` when a layout has several
    /// same-size pictures. A leading `@` in the key is optional. Applied
    /// after `imagePaths`.
    public var images: [String: String]

    public init(
        title: String? = nil,
        body: String? = nil,
        notes: String? = nil,
        layout: String? = nil,
        blocks: [String: String] = [:],
        imagePaths: [String] = [],
        images: [String: String] = [:]
    ) {
        self.title = title
        self.body = body
        self.notes = notes
        self.layout = layout
        self.blocks = blocks
        self.imagePaths = imagePaths
        self.images = images
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
