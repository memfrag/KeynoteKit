# ``KeynoteModel``

Open, inspect, and edit Apple Keynote documents — slides, text, images,
tables, charts, and animations — as a typed object graph.

## Overview

`KeynoteModel` is the editing layer of KeynoteKit. It parses a `.key` file
into typed records (``KeynoteDocument``), exposes each slide as a DOM-like
``SceneTree`` of nodes with stable identifiers, and provides validated
mutations for everything from text to table cells to build animations.
Documents written back open cleanly in Keynote, with styling intact.

```swift
import KeynoteModel

var document = try KeynoteDocument(contentsOf: URL(filePath: "Deck.key"))
try document.setSlideText(at: 0, .title, to: "Hello from Swift")
try document.duplicateSlide(at: 0)
try document.write(to: URL(filePath: "Edited.key"))
```

Everything here operates on Keynote's real file format — a ZIP of
Snappy-compressed protobuf archives (see the `IWAContainer` module) using
schemas reverse-engineered from the Keynote binary. There is no official
specification; the library's invariants were established empirically and are
verified against Keynote itself.

## Topics

### Essentials

- <doc:EditingDocuments>
- ``KeynoteDocument``

### The scene tree

- <doc:SceneTreeGuide>
- ``SceneTree``
- ``SceneNode``
- ``MediaReference``
- ``Frame``

### Slide content

- ``SlidePlaceholder``
- ``TextReplacement``
- ``SlideTextBlock``
- ``LayoutDescription``
- ``PlaceholderField``

### Element labels

- <doc:ElementLabels>

### Tables and charts

- <doc:TablesAndCharts>
- ``ChartData``

### Animations

- <doc:AnimationsGuide>
- ``SlideTransition``
- ``SlideBuild``
- ``KeynoteEffects``

### Errors

- ``SceneEditError``
- ``SlideOperationError``
- ``SlideContentError``
- ``MediaOperationError``
- ``TableError``
- ``ChartError``
- ``BuildError``
- ``TextBlockError``

### Advanced

- ``ObjectRecord``
- ``ReferenceRewriter``
- ``ObjectRecordError``
