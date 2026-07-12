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

## Elements

Three element kinds are built by free functions:

- ``Text(_:)`` — a text box holding the given string.
- ``Image(path:)`` — an image, its file resolved against the writer's
  `imageBaseURL`.
- ``Shape()`` — a rectangle you can fill and size.

Shapes and images are **synthesized from scratch** — their records are built
directly and reference the theme's shape and media styles, so a fill or a
frame behaves exactly as it would on a template element. Text boxes are
cloned from a bundled prototype, because a text box's paragraph and
character style tables are impractical to build from nothing; the clone
supplies a real base style for ``Text`` to vary.

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

### Colors

- ``RGBAColor``
