# Generating Presentations

Describe a deck as data and write it to a `.key` file.

## The model

A ``Presentation`` is a list of ``Slide`` values. Each slide carries the
content to fill in: `title`, `body`, presenter `notes`, a `layout` name
(when building against a multi-layout template), and `imagePaths`.

Build one directly:

```swift
let deck = Presentation(slides: [
    Slide(title: "Q3 Review", body: "Results and outlook", layout: "title"),
    Slide(title: "Highlights",
          body: "Revenue up 40%\nChurn at an all-time low",
          notes: "Pause here for questions.",
          layout: "bullets"),
])
```

Or with the result builder, which supports loops and conditionals:

```swift
let regions = ["EMEA", "APAC", "Americas"]

let deck = Presentation {
    Slide(title: "Regional results", layout: "section")
    for region in regions {
        Slide(title: region, body: "…", layout: "bullets")
    }
    if includeAppendix {
        Slide(title: "Appendix", layout: "section")
    }
}
```

`nil` fields leave the template slide's existing content in place; empty
strings clear it.

## Writing

``KeynoteWriter`` maps the presentation onto a template document:

```swift
let writer = try KeynoteWriter()                     // bundled seed
// or:
let writer = try KeynoteWriter(templateURL: URL(filePath: "Brand.key"))

try writer.write(deck, to: URL(filePath: "Out.key"),
                 imageBaseURL: URL(filePath: "assets/"))
```

How content lands:

- **Slide count** — the template grows (by cloning) or shrinks (by removing
  slides) to match the presentation.
- **Layout selection** — each slide's `layout` picks which template slide to
  clone; see <doc:TemplateDecks>. Without a template that declares layouts,
  every slide clones the seed's first slide.
- **Text routing** — a slide with both title and body maps them directly.
  A slide with a single text block puts it in the layout's *prominent*
  placeholder, inferred per layout as the larger of title/body — which is
  how a Statement or Quote layout renders its one line big and centered.
- **Images** — each slide's `imagePaths` fill the layout's image nodes,
  largest frame first, so on a photo layout the referenced image becomes
  the picture. Relative paths resolve against `imageBaseURL`.

## Post-processing

``KeynoteWriter/build(_:imageBaseURL:)`` returns the `KeynoteDocument`
instead of writing it, so anything the `KeynoteModel` module can do —
transitions, builds, table data, scene-tree edits — can be applied before
saving:

```swift
import KeynoteModel

var document = try writer.build(deck)
for index in 0..<document.slideCount {
    try document.setSlideTransition(
        at: index,
        to: SlideTransition(effect: KeynoteEffects.dissolve, duration: 0.8)
    )
}
try document.write(to: URL(filePath: "Out.key"))
```
