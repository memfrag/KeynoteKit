# KeynoteKit

A Swift package for reading and generating Apple Keynote `.key` files.

Keynote's file format is a ZIP archive of `.iwa` files — Snappy-compressed
(with Apple's non-standard framing) Protocol Buffer messages using
undocumented, reverse-engineered schemas. KeynoteKit implements this format
natively in Swift, with the goal of enabling programmatic generation of
Keynote presentations and Keynote export from macOS apps.

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
    remove, and reorder
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
    placeholders, images, shapes, groups, movies as typed nodes with stable
    object-identifier handles, roles, prompts, authored text, frames, media
    references, and z-order. Serializes to JSON (shape still evolving).
  - **Node-addressed edit commands** (the AI-facing write interface):
    `setNodeText`, `setNodeFrame`, `setNodeMedia` (replaces image content —
    including unmaterialized theme stock photos, by creating fresh data
    entries with full digest bookkeeping), `deleteDrawable`,
    `reorderDrawables`
  - **Reconciler** (`apply(_:media:)`): mutate a scene tree (or its JSON) and
    apply it back; diffs are translated into the commands above, and edits
    that can't be expressed safely (adding nodes, reparenting, type changes)
    are rejected
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

Build a `.key` in Keynote with one slide per layout you want, and tag each in
its presenter notes:

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
swift run iwatool apply-tree In.key Out.key edited-tree.json
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
