# Element Labels

Tag template elements with explicit `@labels` and address them by name,
instead of relying on roles, prompts, or geometry.

## Overview

When you fill a template, KeynoteKit needs to know which element gets which
content. Heuristics can guess — a placeholder's role, the layout's prompt
text, the largest image — but for a bespoke layout the reliable answer is an
**explicit label** the template author sets. Explicit labels take precedence
over every heuristic.

There are two label channels, and KeynoteKit reads both (a comment wins when
both are present):

- **Comments** — attach a comment to *any* element in Keynote (text box,
  shape, image) and start it with `@`. This is the general mechanism.
- **Image Description** — the accessibility "Description" field in the image
  inspector. Keynote only exposes it for images, so it's the convenient
  choice there.

```swift
// Read the labels a template already carries:
for node in try document.sceneTree(forSlideAt: 0).nodes {
    print(node.id, node.type, node.label ?? "—")
}
// 3959420 shape  @left
// 3959492 shape  @right
// 2652703 image  @hero
```

## Addressing by label

Every content-filling entry point matches an explicit label first:

```swift
// Text, by comment label:
try document.setSlideText(at: 0, block: "left", to: "Left column…")

// An image, by comment or Description label:
try document.setSlideImage(at: 0, matching: "hero", to: photoData)
```

The leading `@` is optional in the key — `"left"` matches an element
commented `@left`. In the builder's DSL these are `Slide.blocks` and
`Slide.images` (see the KeynoteBuilder module's "Generating Presentations"
article).

## Reading and writing labels directly

```swift
try document.nodeComment(nodeID)                    // an element's comment text
try document.setNodeDescription(imageID, to: "@hero")   // an image's Description
```

## Keeping output clean

`@label` comments are authoring scaffolding, not review comments.
``KeynoteDocument/stripLabelComments()`` removes every comment whose text
begins with `@` (leaving genuine comments intact), and the builder calls it
automatically — so labels never ship in a generated deck.

```swift
try document.stripLabelComments()
```
