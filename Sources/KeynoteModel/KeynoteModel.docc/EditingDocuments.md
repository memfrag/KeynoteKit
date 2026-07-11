# Editing Documents

Open a `.key` file, change its slides and content, and write it back.

## Overview

``KeynoteDocument`` is the entry point: it reads a Keynote file into typed
records and writes them back as a file Keynote opens without complaint.
Reading and writing are lossless for everything you don't touch — untouched
records reserialize byte-identically.

```swift
import KeynoteModel

var document = try KeynoteDocument(contentsOf: URL(filePath: "Deck.key"))
print(document.slideCount)
try document.write(to: URL(filePath: "Copy.key"))
```

`KeynoteDocument` is a value type. Mutations require `var`, and passing a
document around copies it cheaply.

## Slide text

Each slide exposes its placeholders through ``SlidePlaceholder``: the title,
the body, and the presenter notes.

```swift
let title = try document.slideTitle(at: 0)          // "Q3 Review"
let body = try document.slideBody(at: 0)            // bullet text
let notes = try document.slideNotes(at: 0)          // presenter notes

try document.setSlideText(at: 0, .title, to: "Q4 Review")
try document.setSlideText(at: 0, .body, to: "First point\nSecond point")
try document.setSlideText(at: 0, .notes, to: "Keep the intro short.")
```

Newlines become paragraph breaks (Keynote stores them as U+2029). Setting
text replaces the placeholder's content as a single uniformly-styled run —
the style comes from the slide's layout.

For find-and-replace across the whole document (every text storage, not just
placeholders), use ``TextReplacement``:

```swift
let count = try TextReplacement.replace("ACME", with: "Initech", in: &document)
```

## Slide operations

Slides can be duplicated, removed, and reordered. Duplication deep-copies
the slide's entire component — drawables, text, styles wiring, animations —
under fresh identifiers, so the copy is fully independent:

```swift
let newSlideRootID = try document.duplicateSlide(at: 0)  // copy inserted at index 1
try document.moveSlide(from: 1, to: 3)
try document.removeSlide(at: 2)
```

Duplicating is also the recommended way to "create" a slide with a
particular look: keep a template slide styled the way you want, clone it,
then fill it in. The `KeynoteBuilder` module automates exactly this pattern.

## Images and media

Replace an image's content while keeping its position, size, and crop:

```swift
let photo = try Data(contentsOf: URL(filePath: "team.jpg"))

// By original file name (as listed in `mediaFileNames`):
try document.replaceImage(named: "placeholder.jpg", with: photo)

// Or by scene-tree node id (works for theme stock photos too):
try document.setNodeMedia(imageNodeID, to: photo)
```

Media replacement maintains Keynote's integrity bookkeeping — SHA-1 digests
in two metadata tables, and thumbnail variants re-rendered at their own
size. (Two media entries must never share a digest; the library guarantees
this for you.)

## Layouts and masters

Every slide is based on a master ("slide layout") from the document's theme.
Inspect what a slide's layout offers before filling it:

```swift
let master = try document.slideMasterName(at: 0)     // "Title & Bullets"
let layout = try document.layoutDescription(at: 0)
for field in layout.fields {
    print(field.role, field.prompt ?? "", field.frame ?? "")
}
// title  "Slide Title"       Frame(x: 95, y: 85, ...)
// body   "Slide bullet text" Frame(x: 95, y: 334, ...)
```

``LayoutDescription`` includes each placeholder's role, the master's prompt
text (the strongest hint of what the field is for), its content type (text
or media), and its geometry — enough for a tool or an AI to decide how to
fill a slide without hard-coding theme knowledge.

## Verifying your output

The only authoritative validator for a `.key` file is Keynote itself. During
development, script it:

```bash
osascript -e 'tell application id "com.apple.Keynote"
    set d to open POSIX file "/path/to/Edited.key"
    export d to POSIX file "/tmp/check.pdf" as PDF
    close d saving no
end tell'
```

A repair prompt or a refusal to open means a bookkeeping invariant was
violated — please file an issue with the reproduction.
