import Foundation
import KeynoteModel

/// A color with components in 0…1.
public struct RGBAColor: Sendable, Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let white = RGBAColor(red: 1, green: 1, blue: 1)
    public static let black = RGBAColor(red: 0, green: 0, blue: 0)
    public static func rgb(_ r: Double, _ g: Double, _ b: Double) -> RGBAColor {
        RGBAColor(red: r, green: g, blue: b)
    }
}

/// Geometry and style a canvas element carries. Modifiers accumulate here;
/// the renderer applies the ones relevant to each element kind.
public struct ElementStyle: Sendable, Equatable {
    public var frame: Frame?
    public var fontSize: Double?
    public var bold: Bool?
    public var italic: Bool?
    public var foregroundColor: RGBAColor?
    public var fill: RGBAColor?

    public init() {}
}

/// One element in a ``Canvas`` — text, an image, or a shape. Realized by
/// cloning a prototype from the bundled palette and applying the element's
/// content and modifiers, so it inherits valid Keynote structure and styling
/// before your overrides.
public struct Element: Sendable {
    public enum Kind: Sendable {
        case text(String)
        case image(path: String)
        case shape
    }

    public var kind: Kind
    public var style: ElementStyle

    init(_ kind: Kind, style: ElementStyle = ElementStyle()) {
        self.kind = kind
        self.style = style
    }

    // MARK: Modifiers (SwiftUI-style, chainable)

    /// Positions and sizes the element (slide points; origin top-left).
    public func frame(x: Double, y: Double, width: Double, height: Double) -> Element {
        modifying { $0.frame = Frame(x: x, y: y, width: width, height: height) }
    }

    /// Moves the element, keeping its current (or the prototype's) size.
    public func position(x: Double, y: Double) -> Element {
        modifying {
            let size = $0.frame
            $0.frame = Frame(x: x, y: y, width: size?.width ?? 0, height: size?.height ?? 0)
        }
    }

    public func fontSize(_ size: Double) -> Element { modifying { $0.fontSize = size } }
    public func bold(_ on: Bool = true) -> Element { modifying { $0.bold = on } }
    public func italic(_ on: Bool = true) -> Element { modifying { $0.italic = on } }
    public func foregroundColor(_ color: RGBAColor) -> Element { modifying { $0.foregroundColor = color } }
    /// Fill color, for shape elements.
    public func fill(_ color: RGBAColor) -> Element { modifying { $0.fill = color } }

    private func modifying(_ change: (inout ElementStyle) -> Void) -> Element {
        var copy = self
        change(&copy.style)
        return copy
    }
}

/// Text element.
public func Text(_ string: String) -> Element { Element(.text(string)) }
/// Image element (file path resolved against the writer's `imageBaseURL`).
public func Image(path: String) -> Element { Element(.image(path: path)) }
/// A shape element.
public func Shape() -> Element { Element(.shape) }

/// A free-form slide built from absolutely-positioned elements, rather than
/// from a template layout's placeholders.
public struct Canvas: Sendable {
    public var elements: [Element]

    public init(elements: [Element]) { self.elements = elements }
    public init(@ElementBuilder _ content: () -> [Element]) { self.elements = content() }
}

@resultBuilder
public enum ElementBuilder {
    public static func buildExpression(_ element: Element) -> [Element] { [element] }
    public static func buildExpression(_ elements: [Element]) -> [Element] { elements }
    public static func buildBlock(_ groups: [Element]...) -> [Element] { groups.flatMap { $0 } }
    public static func buildArray(_ groups: [[Element]]) -> [Element] { groups.flatMap { $0 } }
    public static func buildOptional(_ elements: [Element]?) -> [Element] { elements ?? [] }
    public static func buildEither(first elements: [Element]) -> [Element] { elements }
    public static func buildEither(second elements: [Element]) -> [Element] { elements }
}
