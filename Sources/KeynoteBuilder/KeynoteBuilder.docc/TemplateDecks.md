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

The fastest path is the bundled script, which turns a Keynote theme into a
full template — one tagged slide per master the theme defines (Apple's basic
themes carry 17). It accepts an installed theme by name, a custom theme file
(`.kth`), or any existing document:

```bash
scripts/make-template.sh "Basic Black"   BasicBlack-template.key   # installed theme
scripts/make-template.sh MyBrand.kth     Brand-template.key        # custom .kth
scripts/make-template.sh Existing.key    template.key              # any document
```

A `.kth` is the same container format as a `.key`, so ``KeynoteWriter`` can
also use one *directly* as a template — but a theme file ships with a single
example slide, so you get that one layout for every slide. Running it through
the script above is what unlocks all of the theme's layouts.

Each slide is tagged with its master's name, so `layout: Statement`,
`layout: quote`, and `layout: Title & Bullets` all work immediately.

To author by hand instead:

1. Create a deck in Keynote. Add one slide per layout you want to offer,
   each based on the master (slide layout) that fits.
2. **Type sample text into the title and body placeholders.** An untouched
   placeholder has no style tables in its text storage, so programmatic
   text falls back to default styling — black text, invisible on a dark
   theme. Typing anything ("Title", "Body") materializes the theme's real
   styles, which generated content then inherits.
3. Tag each slide in its **presenter notes** with a line like:

   ```
   @layout: title
   ```

   Anything after that line stays private documentation for template
   authors ("use for the opening slide") — the builder strips the notes
   when filling the slide.
4. For picture layouts, place an image on the slide (any placeholder
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
