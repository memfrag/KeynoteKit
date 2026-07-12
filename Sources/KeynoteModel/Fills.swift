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

    private static func gradientStop(_ stop: GradientStop) -> TSD_GradientArchive.GradientStop {
        TSD_GradientArchive.GradientStop.with {
            $0.color = Self.color(stop.color)
            $0.fraction = Float(stop.location)
            $0.inflection = 0.5
        }
    }
}
