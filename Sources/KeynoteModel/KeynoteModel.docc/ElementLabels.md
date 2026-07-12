# Names and Comments

Address elements by their Object List name, and read comments as intent.

## Two distinct channels

KeynoteKit keeps identity and intent separate:

- **Name** — every element's name in Keynote's **Object List** (double-click
  to rename). It's stored as the element's accessibility description and works
  on *any* element — text box, shape, image. KeynoteKit uses the name as the
  **tag** to address an element by. This is `SceneNode.label`.
- **Comment** — a comment attached to an element carries free-form **intent**:
  what the element is for, how it should be used. It's context for a human or
  an AI, never used for addressing. This is `SceneNode.comment`.

So: name the thing you want to find; comment the thing you want to explain.

```swift
for node in try document.sceneTree(forSlideAt: 0).nodes {
    print(node.id, node.type, node.label ?? "—", node.comment ?? "")
}
// 3959420 shape  left-column   "intro copy, keep to two lines"
// 2652703 image  hero          "swap per customer"
```

## Addressing by name

Every content-filling entry point matches a name:

```swift
// Text, by the block's name:
try document.setSlideText(at: 0, block: "left-column", to: "Left column…")

// An image, by name:
try document.setSlideImage(at: 0, matching: "hero", to: photoData)
```

In the builder's DSL these are `Slide.blocks` and `Slide.images` (see the
KeynoteBuilder module's "Generating Presentations" article).

## Reading and writing directly

```swift
try document.nodeName(nodeID)                   // the Object List name (the tag)
try document.setNodeName(nodeID, to: "hero")    // name any element
try document.nodeComment(nodeID)                // the comment (intent), read-only
```

`nodeName` / `setNodeName` and `nodeDescription` / `setNodeDescription` are
the same field under two spellings — the Object List name is the accessibility
description.
