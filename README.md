# KeynoteKit

A Swift package for reading and generating Apple Keynote `.key` files.

![Swift 6.0](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)
![Platform macOS 13+](https://img.shields.io/badge/Platform-macOS%2013%2B-000000?logo=apple&logoColor=white)
[![Docs](https://img.shields.io/badge/Docs-DocC-1E6BB8)](https://memfrag.github.io/KeynoteKit/)
[![Tutorial](https://img.shields.io/badge/Tutorial-JSON%20decks-4CD9C2)](https://memfrag.github.io/KeynoteKit/tutorial.html)

Keynote's file format is a ZIP archive of `.iwa` files — Snappy-compressed
(with Apple's non-standard framing) Protocol Buffer messages using
undocumented, reverse-engineered schemas. KeynoteKit implements this format
natively in Swift, with the goal of enabling programmatic generation of
Keynote presentations and Keynote export from macOS apps.

These three slides were generated from JSON specs (`Examples/Otters.json`,
`Examples/Otters2.json`) with `iwatool build-json` — full-bleed photos,
gradients, masked images, colored bullets, and per-bullet build animations, all
on a 16:9 canvas:

<p align="center">
  <img src="Docs/images/otters-intro.jpg" width="32%" alt="Title slide: 'Otters' over a scrimmed full-bleed lake photo." />
  <img src="Docs/images/otters-content.jpg" width="32%" alt="Editorial content slide: half-bleed otter photo beside a text panel with a coral seam." />
  <img src="Docs/images/otters-split.jpg" width="32%" alt="Split content slide: text column with aqua bullets beside a rounded, shadowed photo card." />
</p>

## Status

Early development. Working today:

- **`IWAContainer`** — the container codec layer:
  - Raw Snappy compressor/decompressor in pure Swift
  - Apple's IWA chunk framing (4-byte headers, no stream identifier, no CRC-32C)
  - `TSP.ArchiveInfo` record framing with byte-stable reserialization
  - `.key` zip archive reading/writing (stored entries, matching Keynote's output)
- **`KeynoteSchemas`** — typed protobuf messages for all 600+ iWork archive
  types, generated with [swift-protobuf](https://github.com/apple/swift-protobuf)
  from the schemas extracted by
  [keynote-parser](https://github.com/psobot/keynote-parser) (currently
  Keynote 14.4), plus the numeric type-ID → message-type registry
- **`KeynoteModel`** — object-graph layer:
  - Parse a document into typed records; decode/mutate/re-encode any archive
    with correct `MessageInfo.length` bookkeeping
  - Document-wide text find/replace over `TSWP.StorageArchive`
  - **Slide operations**: duplicate (deep-copies the slide's `.iwa` component
    with fresh identifiers, rewriting internal references while preserving
    external style/theme references, and maintaining all package metadata),
    remove, reorder, and set the slide (canvas) size (`setSlideSize`, e.g.
    1920×1080 for 16:9)
  - **Image replacement**: swaps a `Data/` image in place, re-renders the
    Keynote-generated preview at its original size, and updates the SHA-1
    digests in both `PackageMetadata` and `DocumentMetadata`
  - Schema-guided wire-format walking (`ReferenceRewriter` +
    generated `MessageFieldMap`) to find/rewrite every `TSP.Reference` in any
    payload without full decoding
  - Per-slide title/body reading and editing (`slideTitle`/`setSlideText`),
    navigating `SlideArchive` → placeholder → `StorageArchive`
  - Layout introspection (`layoutDescriptions()`): for each slide, its master
    and every fillable placeholder with role, kind, prompt text, content type
    (text/media), and geometry — enough for a tool or AI to decide how to fill
    a template without hard-coding theme knowledge
  - **Scene tree**: a DOM-like view of each slide (`sceneTree(forSlideAt:)`) —
    placeholders, images, shapes, groups, movies, and tables as typed nodes
    with stable object-identifier handles, roles, prompts, authored text,
    frames, media references, table cell grids, and z-order. Serializes to
    JSON (shape still evolving).
  - **Table cells**: read any table's grid (`tableCells`) and edit cells
    (`setTableCellText`/`setTableCellNumber`) — decodes and rebuilds the
    binary v5 tile storage, manages the shared string list's refcounts, and
    encodes numbers in Keynote's base-10 decimal format. Edit `cells` in a
    scene tree (or `iwatool set-cell`) to change table content; structure
    (row/column count) is fixed — clone a template table sized to fit.
  - **Slide transitions**: read/set/remove (`slideTransition(at:)`,
    `setSlideTransition(at:to:)`) with effect (`"apple:dissolve"`,
    `"apple:push"`, …), duration, delay, auto-advance, and effect
    parameters — direction, color (Fade Through Color), text delivery,
    twist/mosaic/bounce/motion-blur/travel-distance; editable as
    `transition` on the scene tree.
  - **Chart data**: read and replace any chart's grid (`chartData`/
    `setChartData`) — row names, series names, and values, including
    changing the grid's dimensions; editable as `chart` on the scene tree.
  - **Element builds**: read a slide's animations in playback order
    (`slideBuilds(at:)`), add build-ins/outs to any drawable
    (`addBuild(_:toSlideAt:)` with effects like `"apple:dissolve"`,
    `"apple:bc-appear"`), and remove them (`removeBuild`). Parameters:
    text delivery (by object/word/character/line), delivery direction,
    effect direction, and action-build rotation/scale/opacity.

  Effect names are open strings (Keynote doesn't validate them — an unknown
  name simply doesn't animate), spanning two families: classic `apple:*`
  names and plugin effects (`com.apple.iWork.Keynote.KLNConfetti`, …).
  **`KeynoteEffects`** catalogs the known-good identifiers — 42 transitions,
  40 build-ins, 39 build-outs, and 10 actions, extracted from decks authored
  in Keynote 15.2.1 (raw data in `catalog/`) — plus convenience constants
  (`KeynoteEffects.dissolve`, `.confetti`, `.magicMove`, …). List them with
  `iwatool effects [transitions|build-ins|build-outs|actions]`. For anything
  not cataloged: apply it in Keynote, save, and inspect with `iwatool tree` /
  `iwatool builds`.
  - **Node-addressed edit commands** (the AI-facing write interface):
    `setNodeText`, `setNodeFrame`, `setNodeMedia` (replaces image content —
    including unmaterialized theme stock photos, by creating fresh data
    entries with full digest bookkeeping), `deleteDrawable`,
    `reorderDrawables`, and `cloneDrawable` — nodes are *added* by cloning an
    existing drawable (from any slide, e.g. a template slide), never
    synthesized from scratch, so styles and structure stay valid
  - **Reconciler** (`apply(_:media:)`): mutate a scene tree (or its JSON) and
    apply it back; diffs are translated into the commands above. Add a node
    by appending one with `cloneOf` set to an existing drawable's id; its
    text/frame/media edits are applied to the clone. Reparenting and type
    changes are rejected
- **`KeynoteBuilder`** — the high-level API:
  - Describe a `Presentation` of `Slide`s (title, body, presenter notes)
    declaratively and write it to a `.key`. Uses a template strategy — an
    embedded seed deck carrying a real Keynote theme, masters, and stylesheets
    is grown/shrunk to the requested slide count and filled in, so output
    inherits genuine Keynote styling. Point it at your own `.key` template to
    use a branded theme.
  - **Markdown presentations**: a Marp/Deckset-style format
    (`Presentation(markdown:)`) — `---` separates slides, the first heading is
    the title, bullets/paragraphs become the body, `Notes:` (or
    `<!-- notes: … -->`) adds presenter notes, `<!-- layout: quote -->` picks
    a layout, and `![](path)` images are placed into the layout's picture.
  - **Multi-layout templates**: point `KeynoteWriter` at a template `.key`
    whose slides each demonstrate a layout, tagged in their presenter notes
    (`@layout: quote`) or identified by their master (slide-layout) name. Each
    content slide is cloned from the matching template slide, so it inherits
    that layout's real masters and styling. Design the template in Keynote;
    the builder rearranges and fills it.
  - **Canvas DSL**: a SwiftUI-like, free-form layout API (`Canvas { … }`) that
    places `Text`, `Image`, `Shape`, and `Group` elements by absolute frame and
    synthesizes them from scratch. Chainable modifiers cover font (family/face
    + size/bold/italic), color, fill (color/gradient/image), border, shadow,
    opacity, rotation, mask, alignment, bullets/numbers, columns, drop cap, and
    more. `CanvasWriter` renders `[Canvas]` to a `.key` on a themed 16:9 seed.
  - **JSON deck format**: describe a whole deck as JSON and build it with
    `iwatool build-json spec.json out.key` (see below). A companion JSON Schema
    (`Examples/deck.schema.json`) documents the format and can be handed to an
    LLM to generate decks.
- **`iwatool`** — CLI for inspecting, round-tripping, and rewriting `.key` files

Files generated or modified through KeynoteKit open cleanly in Keynote with
styling intact (verified against Keynote-authored fixtures, including scripted
open-and-export-PDF smoke tests — text replacement, image replacement, and
duplicated / removed / reordered slides, plus full decks built from scratch).

Planned next: shapes and tables (M4), then builds / transitions / charts (M5).

## Generating a presentation

```swift
import KeynoteBuilder

let deck = Presentation {
    Slide(title: "KeynoteKit", body: "A Swift package for generating Keynote files")
    Slide(title: "How it works", body: "Start from a themed seed\nFill in each slide")
    Slide(title: "Status", body: "Milestones 1–3 complete")
}

let writer = try KeynoteWriter()          // or KeynoteWriter(templateURL: myTheme)
try writer.write(deck, to: URL(filePath: "Deck.key"))
```

The builder returns a `KeynoteDocument` from `build(_:)` if you want to apply
further edits (e.g. `replaceImage`) before writing.

Or author the deck as markdown:

```markdown
# KeynoteKit

A Swift package for generating Keynote files

Notes: This whole deck was generated from markdown.

---

# What you can do

- Replace text and images
- Add, remove, and reorder slides
- Build decks from markdown
```

```swift
let deck = try Presentation(markdownFileURL: URL(filePath: "talk.md"))
try KeynoteWriter().write(deck, to: URL(filePath: "talk.key"))
```

### Writing a markdown presentation

The format follows the conventions of tools like Marp and Deckset: one
markdown file is the whole deck, slides are separated by `---`.

**Slides.** A line containing only three or more hyphens (`---`) starts a new
slide. Blocks that contain no content at all are skipped, so stray separators
are harmless.

**Front matter.** An optional YAML block fenced by `---` at the very top of
the file (title, author, anything) is ignored — you can keep metadata there
for other tools.

**Title.** The first heading in a slide becomes its title, whatever the
level (`#`, `##`, …). Any *later* headings in the same slide are treated as
body lines.

**Body.** Bullet lines (`-`, `*`, or `+`) and plain paragraphs become the
body, one line each; the bullet markers themselves are stripped (the layout's
list style supplies them). Blank lines are ignored, so paragraphs and bullets
can be mixed freely.

**Presenter notes.** A line starting with `Notes:` begins the notes; that
line and everything after it (until the next slide) goes to the presenter
notes, not the slide. The HTML-comment form `<!-- notes: … -->` works too and
keeps the notes invisible in other markdown renderers.

**Layout.** `<!-- layout: name -->` (or a bare `layout: name` line) picks
which template slide this content is cloned from — see the next section for
how layouts get their names. Without a directive, the writer's
`defaultLayout` ("bullets") is used. Names are matched case-insensitively.

**Images.** `![alt](path)` places the image into the slide's layout — it
replaces the layout's picture (the largest image node, e.g. a Photo layout's
full-bleed stock photo). Relative paths resolve against the markdown file's
directory. Multiple images fill the layout's image nodes largest-first;
references beyond what the layout can show are ignored, so pick a layout
that has a picture.

**Where the text lands.** For a slide with both a title and body they map to
the title and body placeholders directly. A slide with only one text block
puts it in the layout's *prominent* placeholder — inferred per layout as the
larger of the title/body placeholders — which is how a Statement or Quote
slide renders its single line big and centered without any configuration.

A complete example:

```markdown
---
title: Quarterly Review        ← front matter, ignored
---

# Q3 Review
<!-- layout: title -->

Results and outlook

Notes: Welcome everyone. Keep the intro under a minute.

---

# Highlights
<!-- layout: bullets -->

- Revenue up 40%
- Churn at an all-time low
- Two new markets opened

---

# Our best quarter yet.
<!-- layout: statement -->

---

# The new factory
<!-- layout: photo -->

![factory floor](images/factory.jpg)

<!-- notes: Photo taken during the September visit. -->
```

Build it with `swift run iwatool build-md talk.md Deck.key MyTemplate.key`,
or from Swift:

```swift
let deck = try Presentation(markdownFileURL: URL(filePath: "talk.md"))
let writer = try KeynoteWriter(templateURL: URL(filePath: "MyTemplate.key"))
try writer.write(deck, to: URL(filePath: "Deck.key"),
                 imageBaseURL: URL(filePath: "."))
```

### Using a template deck for multiple layouts

Turn any Keynote theme into a template with one tagged slide per master it
defines (Apple's basic themes carry 17 layouts). The source can be an
installed theme by name, a custom theme file (`.kth`), or any document:

```sh
scripts/make-template.sh "Basic Black" BasicBlack-template.key   # installed theme
scripts/make-template.sh MyBrand.kth   Brand-template.key        # custom .kth
swift run iwatool build-md talk.md talk.key Brand-template.key
```

(A `.kth` is the same format as a `.key`, so `KeynoteWriter` accepts one
directly too — but a theme file has just one example slide, so the script
above is what exposes all of the theme's layouts.)

Or build a `.key` in Keynote by hand with one slide per layout you want —
**type sample text into each placeholder** (untouched placeholders carry no
style tables, so generated text would lose the theme's styling) — and tag
each slide in its presenter notes:

```
@layout: title       ← on a slide using the Title layout
@layout: bullets     ← on a Title & Bullets slide
@layout: statement   ← on a Statement slide
```

Then reference layouts from markdown and point the writer at the template:

```markdown
# The big idea
<!-- layout: statement -->

---

# Details
<!-- layout: bullets -->

- First point
- Second point
```

```swift
let writer = try KeynoteWriter(templateURL: URL(filePath: "MyTemplate.key"))
try writer.write(Presentation(markdownFileURL: URL(filePath: "talk.md")),
                 to: URL(filePath: "talk.key"))
```

A layout can also be referenced without a tag, by its master's name (e.g.
`layout: Title & Bullets`) — tags win when both exist. Any theme works,
Apple's or your own: the theme and its masters travel inside the template
file. Use `iwatool describe-template` to see how a template's layouts are
structured (each placeholder's role, prompt text, and geometry).

## Building a deck from JSON

For richer, designed decks — full-bleed images, gradients, shapes, colored
bullets, per-bullet builds — describe the deck as JSON and build it:

```sh
swift run iwatool build-json deck.json out.key
```

The format maps onto the Canvas DSL. A deck is `slides`, each an ordered list
of `elements` placed by `frame` on a 16:9 (1920×1080) canvas, plus an optional
`background`, `transition`, and `builds`:

```json
{
  "$schema": "./deck.schema.json",
  "defaultFont": "Helvetica Neue",
  "imageBaseDir": "assets",
  "slides": [
    {
      "background": "#0E2529",
      "transition": { "effect": "apple:push", "duration": 0.4, "direction": "fromBottom" },
      "elements": [
        { "type": "image", "image": "lake.jpg", "frame": { "mode": "cover" } },
        { "type": "text", "text": "Otters", "frame": {"x":120,"y":700,"width":1680,"height":220},
          "font": "Futura", "fontSize": 200, "bold": true, "color": "#EDF7F5", "alignment": "center" },
        { "type": "text", "name": "points", "text": "First\nSecond\nThird",
          "frame": {"x":120,"y":520,"width":760,"height":420}, "fontSize": 44, "color": "#EDF7F5",
          "bulleted": { "marker": "•", "color": "#4CD9C2" } }
      ],
      "builds": [
        { "target": "points", "effect": "apple:fade and move character", "duration": 0.3,
          "delivery": "By Paragraph", "textDelivery": "byObject", "direction": "fromBottom",
          "travelDistance": 0.07 }
      ]
    }
  ]
}
```

Highlights:

- **Colors** are a hex string (`"#RRGGBB"` / `"#RRGGBBAA"`) or a `[r,g,b(,a)]`
  array of 0…1 floats. A bare color is also accepted anywhere a fill is expected.
- **Frames** are explicit `{x,y,width,height}` or a helper —
  `{"mode":"cover"}` (full-bleed), `{"mode":"fit","box":{…}}`, or
  `{"mode":"coverBox","box":{…}}` — which read the image's pixel dimensions to
  compute the aspect, so image layouts need no hard-coded ratios.
- **Fonts**: a deck-level `defaultFont`, overridable per element (`font`) and in
  `paragraphStyles`; `bold`/`italic` apply as traits.
- **Images** are file paths (resolved against `imageBaseDir`) or `data:`/base64.
- **Builds** reference an element by `name`; the array order is playback order.
  "By Paragraph" delivery animates one bullet at a time.
- **Nested bullets**: prefix a line in a bulleted element's `text` with tab
  characters — one tab per level (`"Top\n\tNested\n\t\tDeeper"`). Keynote stores
  the level per paragraph; the tabs are stripped.
- **Reusable templates**: define named element sets under `templates` and
  instantiate them per slide with `use` + `set` (fill by element name).
- **External templates**: set a deck-level `template` (a `.key`); a slide then
  `from`s one of its layouts and fills placeholders via `set` (title / body /
  named blocks / images) and named-node `override`s — inheriting the template's
  real masters.
- **Mix all three**: in one deck, `from` (Keynote-template), free-form
  (`elements`), and `use` (inline-template) slides can be interleaved freely.
  Free-form/`use` slides are synthesized onto a blanked scratch layout; note
  their text inherits the template theme's default alignment.

Validation is fail-fast: an invalid spec reports **every** problem at once
(with a `slides[i].elements[j]` path) and writes nothing. The full grammar,
with a `description` on every field, lives in `Examples/deck.schema.json`;
`Examples/Otters.json` and `Examples/Otters2.json` are complete worked decks.

## Usage

```sh
swift build
swift test

# Inspect a .key file
swift run iwatool info MyPresentation.key

# Unpack, re-encode every .iwa with KeynoteKit's codec, repack, verify
swift run iwatool roundtrip MyPresentation.key Repacked.key

# Print all text in a presentation
swift run iwatool text MyPresentation.key

# Replace text across a presentation
swift run iwatool replace In.key Out.key "old text" "new text"

# Slide operations (0-based indices)
swift run iwatool duplicate-slide In.key Out.key 0
swift run iwatool remove-slide In.key Out.key 2
swift run iwatool move-slide In.key Out.key 0 3

# Replace an image (by its original file name)
swift run iwatool list-media In.key
swift run iwatool replace-image In.key Out.key photo.jpg new-photo.jpg

# Build a deck from a text outline ("# " starts a slide; other lines are body)
swift run iwatool build outline.txt Deck.key

# Build a deck from a markdown presentation (optionally with a layout template)
swift run iwatool build-md talk.md Deck.key
swift run iwatool build-md talk.md Deck.key MyTemplate.key

# Build a designed deck from a JSON spec (see "Building a deck from JSON")
swift run iwatool build-json deck.json Deck.key

# Show the master (slide layout) each slide uses
swift run iwatool masters Deck.key

# Describe a template's layouts as JSON (role/kind/prompt/frame per placeholder)
swift run iwatool describe-template MyTemplate.key

# Scene tree: read, edit by node id, or apply an edited tree
swift run iwatool tree Deck.key 2                       # JSON nodes for slide 2
swift run iwatool set-text In.key Out.key 2652722 "New title"
swift run iwatool set-frame In.key Out.key 2652703 100 100 800 450
swift run iwatool set-media In.key Out.key 2652703 photo.jpg
swift run iwatool delete-node In.key Out.key 2652817
swift run iwatool clone-node In.key Out.key 2652817 4      # add: clone node onto slide 4
swift run iwatool set-cell In.key Out.key 2652488 1 2 "31500"   # table cell (row 1, col 2)
swift run iwatool set-transition In.key Out.key 0 apple:dissolve 1.5
swift run iwatool builds Deck.key 0                             # list animations
swift run iwatool add-build In.key Out.key 0 2652189 In apple:dissolve 1.5
swift run iwatool remove-build In.key Out.key 0 2654110
swift run iwatool apply-tree In.key Out.key edited-tree.json
```

## Documentation

Browse the docs online:

- **[API reference &amp; guides](https://memfrag.github.io/KeynoteKit/)** (DocC)
- **[JSON deck tutorial](https://memfrag.github.io/KeynoteKit/tutorial.html)** — an
  illustrated walkthrough of the JSON format

The package is documented with DocC — API reference plus guide articles
(editing documents, the scene tree, tables & charts, animations, the
markdown format, the JSON deck format, template decks, and the container
format). Build it in Xcode (Product ▸ Build Documentation) or from the command
line:

```sh
swift package generate-documentation --target KeynoteModel
swift package generate-documentation --target KeynoteBuilder
swift package generate-documentation --target IWAContainer

# or browse locally:
swift package --disable-sandbox preview-documentation --target KeynoteModel
```

## Regenerating the schemas

The vendored `.proto` files (see `proto/`) come from keynote-parser, which
extracts them from the Keynote application binary. To regenerate the Swift
code for a new schema version:

```sh
PROTOC=/path/to/protoc PROTOC_GEN_SWIFT=/path/to/protoc-gen-swift \
  scripts/gen-protos.sh 14.4
```

## Acknowledgements

The format understanding builds on prior reverse-engineering work:

- [psobot/keynote-parser](https://github.com/psobot/keynote-parser)
- [obriensp/iWorkFileFormat](https://github.com/obriensp/iWorkFileFormat)
- [Reverse Engineering iWork](https://andrews.substack.com/p/reverse-engineering-iwork) by Andrew Sampson
- [eth-siplab/SVG2Keynote-lib](https://github.com/eth-siplab/SVG2Keynote-lib)

Keynote is a trademark of Apple Inc. This project is not affiliated with or
endorsed by Apple. The file format is undocumented and may change with any
Keynote release.
