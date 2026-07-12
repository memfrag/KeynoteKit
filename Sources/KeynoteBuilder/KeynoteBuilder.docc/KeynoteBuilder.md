# ``KeynoteBuilder``

Generate Keynote presentations declaratively — from Swift, from markdown,
from template decks, from free-form Canvas layouts, and from JSON.

## Overview

`KeynoteBuilder` sits on top of `KeynoteModel` and turns a description of a
deck into a real `.key` file. It uses the *template strategy*: rather than
synthesizing slides from nothing, it starts from a seed document that
carries a genuine Keynote theme (masters, stylesheets, placeholders),
clones the right slide for each piece of content, and fills it in. Output
inherits real Keynote styling by construction.

```swift
import KeynoteBuilder

let deck = Presentation {
    Slide(title: "KeynoteKit", body: "Generate Keynote files from Swift")
    Slide(title: "How it works", body: "Clone a themed seed\nFill in each slide")
}

let writer = try KeynoteWriter()
try writer.write(deck, to: URL(filePath: "Deck.key"))
```

The bundled seed is a minimal one-layout deck. For real work, point
``KeynoteWriter`` at your own template — any `.key` file, using any Apple
theme or a custom one — and tag its slides with the layouts they demonstrate
(see <doc:TemplateDecks>).

## Topics

### Building presentations

- <doc:GeneratingPresentations>
- ``Presentation``
- ``Slide``
- ``SlideBuilder``
- ``KeynoteWriter``
- ``KeynoteWriterError``

### Markdown

- <doc:MarkdownFormat>
- ``MarkdownPresentation``

### Templates

- <doc:TemplateDecks>
- ``TemplateLibrary``

### Free-form layouts

- <doc:CanvasLayouts>
- ``Canvas``
- ``Element``
- ``CanvasWriter``
- ``RGBAColor``

### JSON deck format

- <doc:JSONFormat>
- ``DeckSpec``
- ``DeckSpecLoader``
- ``SlideSpec``
- ``ElementSpec``
