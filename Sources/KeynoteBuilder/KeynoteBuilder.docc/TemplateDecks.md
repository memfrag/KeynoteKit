# Template Decks

Design layouts in Keynote once; generate any number of decks from them.

## The idea

A template is an ordinary `.key` file whose slides each demonstrate one
layout — built in Keynote, where masters, styles, and placeholders are
correct by construction. ``KeynoteWriter`` clones the matching example
slide for each piece of content instead of synthesizing anything. This is
how generated decks inherit real Keynote styling, and it works with any
theme, Apple's or your own.

## Authoring a template

1. Create a deck in Keynote. Add one slide per layout you want to offer,
   each based on the master (slide layout) that fits.
2. Tag each slide in its **presenter notes** with a line like:

   ```
   @layout: title
   ```

   Anything after that line stays private documentation for template
   authors ("use for the opening slide") — the builder strips the notes
   when filling the slide.
3. For picture layouts, place an image on the slide (any placeholder
   image); generated images replace it. For decks with tables, size the
   table to fit your data — cell *content* is fillable, structure is not.

``TemplateLibrary`` indexes the deck by those tags **and** by each slide's
master name, so `layout: quote`, `@layout: Quote`, and a slide based on the
"Quote" master all resolve to the same entry (tags win on conflict, and
matching is case-insensitive):

```swift
let library = try TemplateLibrary(templateURL: URL(filePath: "Brand.key"))
print(library.availableLayouts)   // ["bullets", "photo", "quote", "section", "title", …]
```

## Using it

```swift
let writer = try KeynoteWriter(templateURL: URL(filePath: "Brand.key"))
let deck = Presentation {
    Slide(title: "Welcome", layout: "title")
    Slide(title: "Agenda", body: "One\nTwo\nThree", layout: "bullets")
    Slide(title: "Ship it.", layout: "statement")
}
try writer.write(deck, to: URL(filePath: "Out.key"))
```

Requesting a layout the template doesn't define throws
``KeynoteWriterError/unknownLayout(requested:available:)`` listing what is
available. Slides that don't name a layout use ``KeynoteWriter/defaultLayout``
(`"bullets"` unless you change it), falling back to the template's first
slide.

## Inspecting a template

To see what each layout offers — for documentation, debugging, or for an
AI deciding how to fill slides — dump the structure as JSON:

```bash
iwatool describe-template Brand.key
```

Each slide is reported with its tag, master name, and every fillable
placeholder's role, kind, prompt text ("Slide Title", "“Notable Quote”"),
content type, and geometry. The scene tree (`iwatool tree`) gives the same
view with full node detail.
