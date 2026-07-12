# Free-form Canvas Layouts

Compose a slide element by element, with a SwiftUI-like DSL.

## When to use a canvas

The template strategy (<doc:GeneratingPresentations>) fills the placeholders
a layout already defines — a title here, a body there. A ``Canvas`` is the
opposite: you place each element yourself, by absolute position, with no
layout dictating what may appear. Use it when you want an arbitrary
arrangement — several text blocks, images, and shapes wherever you want
them — rather than a title-and-bullets template.

```swift
import KeynoteBuilder

let canvas = Canvas {
    Text("Composed with a DSL")
        .frame(x: 60, y: 60, width: 840, height: 120)
        .fontSize(54).bold().foregroundColor(.rgb(0.2, 0.5, 0.95))
    Text("Every element is placed by hand")
        .frame(x: 60, y: 190, width: 840, height: 80)
        .fontSize(28).italic()
    Shape()
        .frame(x: 60, y: 300, width: 360, height: 260)
        .fill(.rgb(0.95, 0.55, 0.15))
    Image(path: "diagram.png")
        .frame(x: 480, y: 300, width: 420, height: 260)
}

let writer = try CanvasWriter()
try writer.write([canvas], to: URL(filePath: "Deck.key"),
                 imageBaseURL: URL(filePath: "assets/"))
```

Each entry in the list becomes one slide.

## Coordinates and slide size

Positions and sizes are in slide points, origin top-left. Keynote's logical
slide sizes — which also double as the 1× export pixel dimensions — are
**1920 × 1080** for a 16:9 (Wide) slide and **1024 × 768** for a 4:3
(Standard) slide. Lay elements out against whichever your seed uses.

## Slide backgrounds

Pass a ``Fill`` as a canvas `background` to set the slide's background —
matching Keynote's inspector: none, a solid color, a gradient (linear or
radial), or an image.

```swift
Canvas(background: .linearGradient(
    stops: [
        GradientStop(color: (0.1, 0.2, 0.6, 1), location: 0),
        GradientStop(color: (0.7, 0.2, 0.5, 1), location: 1),
    ],
    angleDegrees: 90
)) {
    Text("On a gradient").frame(x: 80, y: 80, width: 800, height: 120)
        .fontSize(48).bold().foregroundColor(.white)
}

// Or: .color(0.1, 0.12, 0.2, 1) · .radialGradient(stops:) ·
//     .image(pngData, mode: .scaleToFill) · .none
```

`nil` (the default) keeps the theme's background. The background changes only
that slide — it's applied as a variation of the slide's style, leaving the
shared master untouched.

## Elements

Three element kinds are built by free functions:

- ``Text(_:)`` — a text box holding the given string.
- ``Image(path:)`` — an image, its file resolved against the writer's
  `imageBaseURL`.
- ``Shape()`` — a rectangle you can fill and size.

Every element is **synthesized from scratch** — nothing is cloned. Each
element's records are built directly and reference the seed theme's styles:
a shape style for shapes, a media style for images, and paragraph/character
styles for text. So a fill, a frame, or a font override behaves exactly as
it would on a template element, and the output inherits real theme
typography.

## Modifiers

Modifiers chain, SwiftUI-style, each returning a new ``Element``:

| Modifier | Applies to | Effect |
| --- | --- | --- |
| `.frame(x:y:width:height:)` | all | absolute position and size (slide points, origin top-left) |
| `.position(x:y:)` | all | move, keeping the current size |
| `.fontSize(_:)` | text | point size |
| `.bold(_:)` / `.italic(_:)` | text | weight and slant |
| `.foregroundColor(_:)` | text | text color |
| `.fill(_:)` | shape | fill color |

Colors are ``RGBAColor`` values in 0…1: `.white`, `.black`, or
`.rgb(_:_:_:)`.

Text styling is applied as Keynote's own anonymous *variation* styles, and a
shape's outline is rescaled to its frame, so overridden elements open and
render exactly as authored.

## Images and digests

An image's bytes are registered as a document data blob. Keynote refuses to
open a file that has two data blobs with the same content digest, so
``CanvasWriter`` deduplicates: an image whose bytes match one already in the
document (the same picture used twice, or one that matches a theme asset)
reuses the existing blob instead of adding a colliding copy. You don't have
to think about it — identical images just work.

## Topics

### Composing a canvas

- ``Canvas``
- ``Element``
- ``ElementStyle``
- ``ElementBuilder``
- ``CanvasWriter``
- ``CanvasWriterError``

### Colors and fills

- ``RGBAColor``
- ``Fill``
- ``GradientStop``
- ``ImageFillMode``
