# Animations

Slide transitions and element builds: reading, setting, and the effect
catalog.

## Effect identifiers

Keynote identifies every animation by an internal string in one of two
families: classic `apple:*` names (`"apple:dissolve"`, `"apple:bc-pop"`,
`"apple:3D-cube"`) and plugin effects
(`"com.apple.iWork.Keynote.KLNConfetti"`, `".BUKAnvil"`, …).

The fields that take them are deliberately plain strings: Keynote does not
validate effect names (an unknown one simply doesn't animate), the set
changes between versions, and nothing in the file format distinguishes a
build effect from a transition effect. ``KeynoteEffects`` catalogs the
known-good identifiers — extracted from decks that exercised every effect
in Keynote 15.2.1's UI — split by where they're offered:

```swift
KeynoteEffects.transitions   // 42 identifiers, menu order
KeynoteEffects.buildIns      // 40
KeynoteEffects.buildOuts     // 39
KeynoteEffects.actions       // 10

KeynoteEffects.dissolve      // "apple:dissolve" — common ones as constants
KeynoteEffects.confetti
KeynoteEffects.magicMove
```

To discover the identifier (and parameter encoding) for anything not
cataloged: apply the effect in Keynote, save, and inspect the file with
`iwatool tree` or `iwatool builds`.

## Transitions

A ``SlideTransition`` describes the animation from a slide to the next:

```swift
// Read
if let transition = try document.slideTransition(at: 0) {
    print(transition.effect, transition.duration)
}

// Set
try document.setSlideTransition(at: 0, to: SlideTransition(
    effect: KeynoteEffects.cube,
    duration: 1.5
))

// Remove
try document.setSlideTransition(at: 0, to: nil)
```

Effect parameters are optional fields; omitted ones keep the effect's
defaults:

```swift
try document.setSlideTransition(at: 0, to: SlideTransition(
    effect: KeynoteEffects.fadeThroughColor,
    duration: 1.2,
    color: [1.0, 0.0, 0.0],        // fade through red
    motionBlur: true
))
```

Available parameters: `direction`, `isAutomatic` (auto-advance after
`delay`), `color`, `textDelivery` (`"byObject"`, `"byWord"`,
`"byCharacter"`, `"byLine"`), `twist`, `mosaicSize`, `bounce`,
`motionBlur`, and `travelDistance`.

Transitions are also part of every ``SceneTree`` (its `transition` field),
so they participate in JSON editing and the reconciler.

## Element builds

A ``SlideBuild`` animates one drawable: a build-in (`kind == "In"`),
build-out (`"Out"`), or action (`"Action"`). Reading returns them in
playback order:

```swift
for build in try document.slideBuilds(at: 0) {
    print(build.kind, build.effect, "on node", build.nodeID)
}
```

Add a build to any drawable on the slide (the node ids come from the scene
tree), and remove by the id `slideBuilds` reports:

```swift
let shapeID = tree.nodes.first { $0.type == "shape" }!.id

let buildID = try document.addBuild(SlideBuild(
    nodeID: shapeID,
    kind: "In",
    effect: KeynoteEffects.dissolve,
    duration: 1.5,
    textDelivery: "byWord"
), toSlideAt: 0)

try document.removeBuild(buildID, fromSlideAt: 0)
```

Build parameters: `textDelivery`, `deliveryOption` (`"forward"`/
`"backward"`), `direction`, and — for action builds — `rotationAngle`,
`scaleSize`, and `opacity`.

```swift
// Rotate action: spin the logo 180°
try document.addBuild(SlideBuild(
    nodeID: logoID,
    kind: "Action",
    effect: "apple:action-rotation",
    duration: 2.0,
    rotationAngle: .pi
), toSlideAt: 0)
```

> Note: The bespoke parameters of *plugin* effects (for example Confetti's
> density) use a separate storage mechanism that isn't exposed yet. The
> parameters above cover the classic effect families.
