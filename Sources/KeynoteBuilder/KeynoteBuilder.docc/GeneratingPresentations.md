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

## Layouts with more than a title and body

`title` and `body` cover the common case, but a template slide can have any
number of text regions — two bullet columns, a subtitle, a quote's
attribution, a labeled callout. Fill those with `blocks`, a dictionary
keyed by whatever identifies each region:

```swift
Slide(layout: "two-column", blocks: [
    "header": "Build vs. Buy",
    "left":   "Full control\nOwn the roadmap\nHigher upfront cost",
    "right":  "Faster to ship\nVendor lock-in\nRecurring cost",
])
```

A key matches a region by, in order: its **role** (`"title"`, `"body"`,
`"object"`), the **label** the template author typed into it (type `"left"`
into the left column when authoring the template), or the layout's **prompt**
(`"Attribution"`). Values use `\n` for bullet/paragraph breaks, exactly like
`body`.

This makes nearly arbitrary layouts fillable: design a template slide in
Keynote with as many text boxes as you like, label each with a short word,
and address them by those words. Discover the available keys for any
template slide with:

```bash
iwatool blocks-of MyTemplate.key 0
# node 32224: "header"
# node 32249: "left"
# node 32274: "right"
```

`blocks` is applied after `title`/`body`, and — like everything in the
builder — you can always drop to the scene tree (via ``KeynoteWriter/build(_:imageBaseURL:)``)
to address any node by id for total control.

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
  largest frame first. A photo layout's single picture takes the first path;
  a two-photo layout takes two, largest first:

  ```swift
  Slide(layout: "two-photo", imagePaths: ["before.jpg", "after.jpg"])
  ```

  Relative paths resolve against `imageBaseURL`. For precise control over
  which image lands where (rather than by size), address the image nodes
  directly through the scene tree after ``KeynoteWriter/build(_:imageBaseURL:)``.

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
