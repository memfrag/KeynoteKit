# The JSON deck format

Describe a whole deck as JSON and build it to a `.key`.

## Overview

The JSON format is a declarative, tooling-friendly (and LLM-friendly) mirror of
the Canvas DSL. A ``DeckSpec`` is decoded from JSON and ``DeckSpecLoader``
translates it into a `KeynoteDocument`: free-form slides are synthesized element
by element, transitions and builds are layered on, and — when a `template` is
given — layout slides are cloned from an external `.key` and filled.

Build one from the command line:

```sh
swift run iwatool build-json deck.json out.key
```

The canvas is 16:9 (1920×1080). A companion JSON Schema,
`Examples/deck.schema.json`, documents every field and can be pasted into an LLM
prompt to generate conforming decks. `Examples/Otters.json` and
`Examples/Otters2.json` are complete worked decks.

## A deck

```json
{
  "$schema": "./deck.schema.json",
  "name": "Otters",
  "defaultFont": "Helvetica Neue",
  "imageBaseDir": "assets",
  "paragraphStyles": [ … ],
  "templates": { … },
  "slides": [ … ]
}
```

- `defaultFont` applies to all text unless an element or paragraph style
  overrides it.
- `imageBaseDir` (relative to the spec file) is where image paths resolve;
  it defaults to the spec's own directory.
- `paragraphStyles` are named styles appliable via an element's
  `paragraphStyle`.
- `templates` are reusable in-JSON slide templates (see below).
- `template` (not shown) names an external template `.key` for `from` slides.

## Slides and elements

A free-form slide is an ordered list of `elements` plus an optional
`background`, `transition`, and `builds`:

```json
{
  "background": "#0E2529",
  "transition": { "effect": "apple:push", "duration": 0.4, "direction": "fromBottom" },
  "elements": [
    { "type": "image", "image": "lake.jpg", "frame": { "mode": "cover" } },
    { "type": "text", "text": "Otters",
      "frame": {"x":120,"y":700,"width":1680,"height":220},
      "font": "Futura", "fontSize": 200, "bold": true, "color": "#EDF7F5", "alignment": "center" }
  ]
}
```

An element's `type` is `text`, `image`, `shape`, or `group`, followed by a flat
bag of optional modifiers mirroring the Canvas DSL: `font`, `fontSize`, `bold`,
`italic`, `underline`, `strikethrough`, `color`, `alignment`,
`verticalAlignment`, `fill`, `border`, `shadow`, `opacity`, `rotation`,
`startCap`/`endCap`, `mask`, `paragraphStyle`, `columns`/`columnGap`,
`textInset`, `bulleted`, `numbered`, `dropCap`, `locked`,
`flippedHorizontally`/`flippedVertically`, and `name`.

### Colors

A color is a hex string (`"#RRGGBB"` / `"#RRGGBBAA"`) or a `[r,g,b]` / `[r,g,b,a]`
array of 0…1 floats. A bare color is also accepted anywhere a `fill` is expected
(shorthand for a color fill).

### Frames

A frame is explicit `{x,y,width,height}`, or a helper that reads the element
image's pixel dimensions to compute its aspect:

- `{"mode":"cover"}` — cover-crop the full 1920×1080 canvas.
- `{"mode":"fit","box":{x,y,width,height}}` — aspect-fit centered in the box.
- `{"mode":"coverBox","box":{x,y,width,height}}` — cover-crop into the box.

### Fills and shapes

`fill` is `{"type":"color"|"none"|"linearGradient"|"radialGradient"|"image", …}`
(or a bare color). A `shape` element / `mask` takes
`{"kind":"rectangle"|"roundedRectangle"|"ellipse"|"line"|"regularPolygon"|"star"|"path"|"native", …}`.

### Images

An image (`image` on an element, `image` on a fill/override) is a file path
(resolved against `imageBaseDir`) or a `data:`/base64 blob. Identical images are
deduplicated by the model.

## Transitions and builds

`transition` sets the slide's transition; `direction` accepts the friendly
`fromLeft` / `fromRight` / `fromTop` / `fromBottom`.

`builds` is a slide-level ordered list — array order is playback order. Each
build targets an element by `name`:

```json
"builds": [
  { "target": "points", "kind": "In", "effect": "apple:fade and move character",
    "duration": 0.3, "delivery": "By Paragraph", "textDelivery": "byObject",
    "direction": "fromBottom", "travelDistance": 0.07 }
]
```

`delivery: "By Paragraph"` (with `textDelivery: "byObject"`) animates one
paragraph/bullet at a time. `kind` is `In`, `Out`, or an action type.

## Reusable templates

Define named element sets under `templates`, then instantiate them per slide
with `use` and fill by element `name` with `set`:

```json
{
  "templates": {
    "content": { "elements": [
      { "type": "text", "name": "title", "text": "", "frame": {…}, "fontSize": 84, "bold": true }
    ] }
  },
  "slides": [
    { "use": "content", "set": { "title": { "text": "Playful by Nature" } },
      "elements": [ … extra elements … ] }
  ]
}
```

## External templates

Set a deck-level `template` (a `.key`); each slide then clones one of its
layouts with `from` and fills it:

```json
{
  "template": "brand.key",
  "slides": [
    { "from": { "layout": "Title & Bullets" },
      "set": { "title": "Quarterly Review", "body": "First point\nSecond point" },
      "override": [ { "target": "Hero Photo", "image": "team.jpg" } ] }
  ]
}
```

`from.layout` matches a layout tag or master name (or use `from.slideIndex`).
`set` fills the title / body / named blocks / images; `override` mutates a named
node's text, image, frame, or style. Cloned slides inherit the template's real
masters — so `title` (the navigator/outline title) works here, where free-form
slides have no title placeholder.

## Mixing slide kinds

A deck with a `template` can freely interleave all three kinds — `from`
(clone a layout), free-form (`elements`), and `use` (inline template). `from`
slides clone and fill their layout; free-form/`use` slides are synthesized onto
a blanked scratch layout. (Their text inherits the template theme's default
paragraph alignment, unlike the placeholders on a `from` slide.)

## Nested bullets

Prefix a line in a bulleted element's `text` with tab characters — one tab per
level — to nest it. Keynote stores the level per paragraph (it is not a literal
tab); the tabs are stripped.

```json
{ "type": "text", "bulleted": { "marker": "•" },
  "text": "Otters\n\tRiver otters\n\tSea otters\n\t\tUse tools\nConservation" }
```

## Validation

Validation is fail-fast and exhaustive: an invalid spec reports **every**
problem at once — each with a `slides[i].elements[j]` path — and writes nothing.
Checks include unknown enum values, missing frames, unresolved build/override
targets, missing images, duplicate element names, and unknown layouts.
