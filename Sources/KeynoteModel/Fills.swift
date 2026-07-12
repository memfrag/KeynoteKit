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

/// A decoration on the end of a line.
public enum LineEnd: Sendable {
    case none
    /// A filled triangular arrowhead ("simple arrow").
    case arrow
}

/// A border (stroke) around a shape, text box, or image.
public struct Border: Sendable {
    /// RGBA in 0…1.
    public var color: (Double, Double, Double, Double)
    /// Line width in points.
    public var width: Double

    public init(color: (Double, Double, Double, Double) = (0, 0, 0, 1), width: Double = 1) {
        self.color = color
        self.width = width
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
            $0.cap = .buttCap
            $0.join = .miterJoin
            $0.miterLimit = 4
            $0.pattern = TSD_StrokePatternArchive.with {
                $0.type = .tsdsolidPattern
                $0.count = 0
            }
        }
    }

    /// The archive for a line-end decoration, or `nil` for `.none`. Mirrors
    /// Keynote's "simple arrow" preset (a small filled triangle).
    static func lineEndArchive(_ end: LineEnd) -> TSD_LineEndArchive? {
        switch end {
        case .none:
            return nil
        case .arrow:
            func point(_ x: Double, _ y: Double) -> TSP_Point { TSP_Point.with { $0.x = Float(x); $0.y = Float(y) } }
            return TSD_LineEndArchive.with {
                $0.path = TSP_Path.with {
                    $0.elements = [
                        TSP_Path.Element.with { $0.type = .moveTo; $0.points = [point(0, 0)] },
                        TSP_Path.Element.with { $0.type = .lineTo; $0.points = [point(3, 6)] },
                        TSP_Path.Element.with { $0.type = .lineTo; $0.points = [point(6, 0)] },
                        TSP_Path.Element.with { $0.type = .closeSubpath },
                    ]
                }
                $0.lineJoin = .miterJoin
                $0.endPoint = point(3, 0)
                $0.isFilled = true
                $0.identifier = "simple arrow"
            }
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
