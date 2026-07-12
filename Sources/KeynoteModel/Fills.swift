import Foundation
import KeynoteSchemas

/// A fill for a slide background or a shape.
///
/// Mirrors the fills Keynote's inspector offers: none, a solid color, a
/// gradient (linear or radial — "advanced gradient" is the same archive with
/// more stops/positioning), or an image (with a scaling technique and optional
/// tint — "advanced image fill" is the same archive with a tint).
public enum Fill: Sendable {
    case none
    case color(Double, Double, Double, Double)
    case linearGradient(stops: [GradientStop], angleDegrees: Double)
    case radialGradient(stops: [GradientStop])
    case image(Data, mode: ImageFillMode = .scaleToFill, tint: (Double, Double, Double, Double)? = nil)
}

/// One color stop in a ``Fill`` gradient.
public struct GradientStop: Sendable {
    /// RGBA in 0…1.
    public var color: (Double, Double, Double, Double)
    /// Position along the gradient, 0…1.
    public var location: Double

    public init(color: (Double, Double, Double, Double), location: Double) {
        self.color = color
        self.location = location
    }
}

/// A decoration on the end of a line — Keynote's line-ending presets.
public enum LineEnd: Sendable {
    case none
    /// A filled triangular arrowhead ("simple arrow").
    case arrow
    /// A filled arrowhead with a notched tail ("filled arrow").
    case filledArrow
    /// An open (unfilled) arrowhead ("open arrow").
    case openArrow
    /// A filled arrowhead pointing back along the line ("inverted arrow").
    case invertedArrow
    /// A filled dot ("filled circle").
    case filledCircle
    /// An open (unfilled) dot ("open circle").
    case openCircle
    /// A filled diamond ("filled diamond").
    case diamond
    /// A filled square ("filled square").
    case filledSquare
    /// An open (unfilled) square ("open square").
    case openSquare
    /// A perpendicular bar ("line").
    case bar
}

/// A border (stroke) around a shape, text box, or image — also the stroke of
/// a `Shape(.line)`.
public struct Border: Sendable {
    /// RGBA in 0…1.
    public var color: (Double, Double, Double, Double)
    /// Line width in points.
    public var width: Double
    /// Dash/gap lengths in multiples of the width; empty means a solid line.
    public var dash: [Double]
    /// Round line caps (used for dotted lines).
    public var roundCap: Bool

    public init(
        color: (Double, Double, Double, Double) = (0, 0, 0, 1), width: Double = 1,
        dash: [Double] = [], roundCap: Bool = false
    ) {
        self.color = color
        self.width = width
        self.dash = dash
        self.roundCap = roundCap
    }

    /// A dashed line (dash and gap each `2×` the width).
    public static func dashed(color: (Double, Double, Double, Double) = (0, 0, 0, 1), width: Double = 1) -> Border {
        Border(color: color, width: width, dash: [2, 2])
    }
    /// A dotted line (round dots).
    public static func dotted(color: (Double, Double, Double, Double) = (0, 0, 0, 1), width: Double = 1) -> Border {
        Border(color: color, width: width, dash: [0.001, 2], roundCap: true)
    }
}

/// A drop shadow behind a shape, text box, or image.
public struct Shadow: Sendable {
    /// RGBA in 0…1.
    public var color: (Double, Double, Double, Double)
    /// Distance from the object, in points.
    public var offset: Double
    /// Blur radius, in points.
    public var blur: Double
    /// Direction the shadow is cast, in degrees.
    public var angleDegrees: Double
    /// 0…1.
    public var opacity: Double

    public init(
        color: (Double, Double, Double, Double) = (0, 0, 0, 1),
        offset: Double = 5, blur: Double = 6, angleDegrees: Double = 315, opacity: Double = 0.5
    ) {
        self.color = color
        self.offset = offset
        self.blur = blur
        self.angleDegrees = angleDegrees
        self.opacity = opacity
    }
}

/// How an image fill is scaled into its area.
public enum ImageFillMode: Sendable {
    case original
    case stretch
    case tile
    case scaleToFill
    case scaleToFit

    var technique: TSD_ImageFillArchive.ImageFillTechnique {
        switch self {
        case .original: return .naturalSize
        case .stretch: return .stretch
        case .tile: return .tile
        case .scaleToFill: return .scaleToFill
        case .scaleToFit: return .scaleToFit
        }
    }
}

extension KeynoteDocument {

    /// Builds a `TSD.FillArchive` for a fill, registering image data when
    /// needed. Returns the archive plus any data identifiers it references, so
    /// the caller can record them on the style record that carries the fill.
    /// `.none` yields an empty archive (no color/gradient/image = no fill).
    mutating func makeFillArchive(_ fill: Fill) throws -> (archive: TSD_FillArchive, dataIDs: [UInt64]) {
        switch fill {
        case .none:
            return (TSD_FillArchive(), [])

        case let .color(r, g, b, a):
            return (TSD_FillArchive.with { $0.color = Self.color((r, g, b, a)) }, [])

        case let .linearGradient(stops, angle):
            let archive = TSD_FillArchive.with {
                $0.gradient = TSD_GradientArchive.with {
                    $0.type = .linear
                    $0.opacity = 1
                    $0.stops = stops.map(Self.gradientStop)
                    $0.anglegradient = TSD_AngleGradientArchive.with { $0.gradientangle = Float(angle) }
                }
            }
            return (archive, [])

        case let .radialGradient(stops):
            let archive = TSD_FillArchive.with {
                $0.gradient = TSD_GradientArchive.with {
                    $0.type = .radial
                    $0.opacity = 1
                    $0.stops = stops.map(Self.gradientStop)
                    $0.anglegradient = TSD_AngleGradientArchive.with { $0.gradientangle = 0 }
                }
            }
            return (archive, [])

        case let .image(data, mode, tint):
            let (mainID, _) = try registerImageData(data)
            let archive = TSD_FillArchive.with {
                $0.image = TSD_ImageFillArchive.with {
                    $0.imagedata = TSP_DataReference.with { $0.identifier = mainID }
                    $0.technique = mode.technique
                    $0.interpretsUntaggedImageDataAsGeneric = false
                    if let tint { $0.tint = Self.color(tint) }
                }
            }
            return (archive, [mainID])
        }
    }

    static func strokeArchive(_ border: Border) -> TSD_StrokeArchive {
        TSD_StrokeArchive.with {
            $0.color = Self.color(border.color)
            $0.width = Float(border.width)
            $0.cap = border.roundCap ? .roundCap : .buttCap
            $0.join = .miterJoin
            $0.miterLimit = 4
            $0.pattern = TSD_StrokePatternArchive.with {
                if border.dash.isEmpty {
                    $0.type = .tsdsolidPattern
                    $0.count = 0
                    $0.pattern = Array(repeating: 0, count: 6)
                } else {
                    // The pattern array is fixed at six entries; `count` marks
                    // how many are significant.
                    $0.type = .tsdpattern
                    $0.count = UInt32(border.dash.count)
                    var values = border.dash.map(Float.init)
                    while values.count < 6 { values.append(0) }
                    $0.pattern = Array(values.prefix(6))
                }
            }
        }
    }

    /// The archive for a line-end decoration, or `nil` for `.none`. Geometry
    /// matches Keynote's own presets (verified against an authored deck).
    static func lineEndArchive(_ end: LineEnd) -> TSD_LineEndArchive? {
        typealias E = (String, [(Double, Double)])  // (type, points)
        let m = "moveTo", l = "lineTo", c = "curveTo", z = "closeSubpath"

        // A circle outline reused by filled/open circle.
        let circle: [E] = [
            (m, [(5.5, 3.0)]),
            (c, [(5.5, 4.380712), (4.380712, 5.5), (3.0, 5.5)]),
            (c, [(1.6192881, 5.5), (0.5, 4.380712), (0.5, 3.0)]),
            (c, [(0.5, 1.6192881), (1.6192881, 0.5), (3.0, 0.5)]),
            (c, [(4.380712, 0.5), (5.5, 1.6192881), (5.5, 3.0)]),
            (z, []),
        ]

        let spec: (elements: [E], endPoint: (Double, Double), roundJoin: Bool, filled: Bool, identifier: String)
        switch end {
        case .none:
            return nil
        case .arrow:
            spec = ([(m, [(0, 0)]), (l, [(3, 6)]), (l, [(6, 0)]), (z, [])], (3, 0), false, true, "simple arrow")
        case .filledArrow:
            spec = ([(m, [(0, 0)]), (l, [(3, 6)]), (l, [(6, 0)]), (l, [(3, 1.5)]), (z, [])], (3, 1.5), false, true, "filled arrow")
        case .openArrow:
            spec = ([(m, [(0, 0)]), (l, [(3, 5)]), (l, [(6, 0)]), (m, [(3, 0)]), (l, [(3, 5)])], (3, 0), true, false, "open arrow")
        case .invertedArrow:
            spec = ([(m, [(0, 3)]), (l, [(3, 0)]), (l, [(6, 3)]), (z, [])], (3, 0.3314), false, true, "inverted arrow")
        case .filledCircle:
            spec = (circle, (3, 0.5), false, true, "filled circle")
        case .openCircle:
            spec = (circle, (3, -0.3), false, false, "open circle")
        case .diamond:
            spec = ([(m, [(3, 0)]), (l, [(0, 3)]), (l, [(3, 6)]), (l, [(6, 3)]), (z, [])], (3, 0.3314), false, true, "filled diamond")
        case .filledSquare:
            spec = ([(m, [(0.5, 0.5)]), (l, [(5.5, 0.5)]), (l, [(5.5, 5.5)]), (l, [(0.5, 5.5)]), (z, [])], (3, 0.5), false, true, "filled square")
        case .openSquare:
            spec = ([(m, [(1, 1)]), (l, [(5, 1)]), (l, [(5, 5)]), (l, [(1, 5)]), (z, [])], (3, 0.2), false, false, "open square")
        case .bar:
            spec = ([(m, [(0, 0)]), (l, [(6, 0)])], (3, -0.8), false, false, "line")
        }

        func point(_ p: (Double, Double)) -> TSP_Point { TSP_Point.with { $0.x = Float(p.0); $0.y = Float(p.1) } }
        return TSD_LineEndArchive.with {
            $0.path = TSP_Path.with {
                $0.elements = spec.elements.map { type, points in
                    TSP_Path.Element.with {
                        switch type {
                        case m: $0.type = .moveTo
                        case l: $0.type = .lineTo
                        case c: $0.type = .curveTo
                        default: $0.type = .closeSubpath
                        }
                        $0.points = points.map(point)
                    }
                }
            }
            $0.lineJoin = spec.roundJoin ? .roundJoin : .miterJoin
            $0.endPoint = point(spec.endPoint)
            $0.isFilled = spec.filled
            $0.identifier = spec.identifier
        }
    }

    static func shadowArchive(_ shadow: Shadow) -> TSD_ShadowArchive {
        TSD_ShadowArchive.with {
            $0.color = Self.color(shadow.color)
            $0.angle = Float(shadow.angleDegrees)
            $0.offset = Float(shadow.offset)
            $0.radius = Int32(shadow.blur.rounded())
            $0.opacity = Float(shadow.opacity)
            $0.isEnabled = true
            $0.type = .tsddropShadow
        }
    }

    private static func gradientStop(_ stop: GradientStop) -> TSD_GradientArchive.GradientStop {
        TSD_GradientArchive.GradientStop.with {
            $0.color = Self.color(stop.color)
            $0.fraction = Float(stop.location)
            $0.inflection = 0.5
        }
    }
}
