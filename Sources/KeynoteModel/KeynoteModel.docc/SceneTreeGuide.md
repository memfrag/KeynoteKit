# The Scene Tree

Read a slide as a DOM-like node tree, and edit it by node id or by
mutating the tree and applying it back.

## Overview

``KeynoteDocument/sceneTree(forSlideAt:)`` projects one slide into a
``SceneTree``: the slide's placeholders and free drawables as typed
``SceneNode`` values, in stacking order, with the slide's notes and
transition alongside. Node ids are the document's own object identifiers —
stable handles that survive write/read cycles.

```swift
let tree = try document.sceneTree(forSlideAt: 0)
print(tree.master ?? "?")                 // "Title & Bullets"
for node in tree.nodes {
    print(node.id, node.type, node.role ?? "-", node.text ?? "")
}
// 2652722 placeholder title  "Q3 Review"
// 2652736 placeholder body   "Revenue up 40%…"
// 2652703 image       -
// 2652817 shape       -      "Footnote"
```

`SceneTree` is `Codable`; encoded as JSON it is the interface an external
tool or AI can read and edit. (The JSON shape is still evolving — treat it
as internal.)

Node types: `"placeholder"` (with a `role` of title/body/object/slideNumber
and the master's `prompt` text), `"shape"` (text boxes and shapes),
`"image"`, `"movie"`, `"group"` (with `children`), `"table"` (with `cells`),
`"chart"` (with `chart` data), and `"connectionLine"`.

## Editing by node id

Each mutation validates its target and maintains the document's
bookkeeping (identifier uniqueness, reference tables, media digests):

```swift
// Text of any placeholder or shape:
try document.setNodeText(2652736, to: "New body text")

// Move and resize:
try document.setNodeFrame(2652703, to: Frame(x: 100, y: 100, width: 800, height: 450))

// Replace an image's content — including a theme layout's stock photo:
try document.setNodeMedia(2652703, to: try Data(contentsOf: photoURL))

// Remove a free drawable (placeholders can't be deleted):
try document.deleteDrawable(2652817)

// Restack (back to front; must permute the existing free drawables):
try document.reorderDrawables(onSlideAt: 0, to: [2652817, 2652703])
```

## Adding nodes: clone, don't synthesize

You can *add* elements to a slide, not only replace what a template already
contains — but new drawables are created by **cloning** an existing one,
never synthesized from nothing. The source (from the same slide, another
slide, or a template) supplies valid styles and structure, which is why
cloned content always renders correctly:

```swift
// Add a text box by cloning one, then give it content and a position:
let textID = try document.cloneDrawable(sourceTextNodeID, toSlideAt: 2)
try document.setNodeText(textID, to: "The cloned text box")
try document.setNodeFrame(textID, to: Frame(x: 60, y: 700, width: 600, height: 80))

// Add a second image by cloning the first, then give it independent content:
let imageID = try document.cloneDrawable(sourceImageNodeID, toSlideAt: 2)
try document.setNodeMedia(imageID, to: try Data(contentsOf: photoURL))
try document.setNodeFrame(imageID, to: Frame(x: 950, y: 250, width: 500, height: 375))
```

A cloned image initially shares the source's media data; ``setNodeMedia``
detects this and gives the clone its own fresh data, so replacing one
image's content never disturbs the other.

Keep a "palette" slide of prototype elements — a text box, an image box, a
shape — and clone from it to compose slides element by element.

## Editing the tree wholesale

For bulk edits — and for AI workflows operating on the JSON —
mutate a `SceneTree` and apply it. ``KeynoteDocument/apply(_:media:)``
diffs the edited tree against the document's current state and translates
the differences into the validated commands above:

```swift
var tree = try document.sceneTree(forSlideAt: 0)

for index in tree.nodes.indices where tree.nodes[index].role == "title" {
    tree.nodes[index].text = "Reconciled title"          // text edit
}
tree.nodes.removeAll { $0.id == 2652817 }                // deletion
tree.notes = "Updated speaker notes"                     // notes edit
tree.transition = SlideTransition(effect: KeynoteEffects.dissolve)

// Add a node by cloning (id 0 is a placeholder; edits apply to the clone):
tree.nodes.append(SceneNode(
    id: 0, type: "shape",
    text: "Added via reconcile",
    frame: Frame(x: 50, y: 60, width: 700, height: 80),
    cloneOf: 2652736
))

try document.apply(tree)
```

Media replacement through the tree takes either a `replaceWith` file path on
the node's ``MediaReference`` (handy in JSON), or an explicit dictionary:

```swift
try document.apply(tree, media: [imageNodeID: newImageData])
```

Edits that can't be expressed as safe operations — inventing nodes without
`cloneOf`, reparenting, changing a node's type or role — are rejected with
``SceneEditError/unsupportedEdit(_:)`` rather than guessed at.

## From the command line

The same three interfaces exist in `iwatool`:

```bash
iwatool tree Deck.key 0 > slide0.json      # read
iwatool set-text  Deck.key Out.key 2652736 "New text"
iwatool set-frame Deck.key Out.key 2652703 100 100 800 450
iwatool set-media Deck.key Out.key 2652703 photo.jpg
iwatool delete-node Deck.key Out.key 2652817
iwatool clone-node  Deck.key Out.key 2652736 2
iwatool apply-tree  Deck.key Out.key edited.json
```
