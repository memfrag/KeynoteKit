// Verified animation-effect identifiers, extracted from decks authored in
// Keynote 15.2.1 (catalog/effects-keynote-15.2.1.json holds the raw data).
// Effect names are open strings -- Keynote accepts unknown ones without
// complaint (they simply don't animate) -- so these lists are a catalog of
// known-good values, not a closed set. To discover an identifier for a UI
// effect not listed here: apply it in Keynote, save, and inspect with
// `iwatool tree` / `iwatool builds`.

/// Known-good animation effect identifiers, by category.
public enum KeynoteEffects {

    /// Slide transitions, in Keynote 15's menu order.
    public static let transitions: [String] = [
        "apple:magic-move-implied-motion-path",
        "apple:ClotheslinePush",
        "com.apple.iWork.Keynote.KLNConfetti",
        "apple:dissolve",
        "apple:bounce",
        "apple:droplet",
        "apple:fade-and-move",
        "com.apple.iWork.Keynote.BLTFadeThruColor",
        "apple:apple-grid",
        "apple:wipe-iris",
        "apple:slide",
        "apple:push",
        "apple:reveal",
        "apple:FlipThrough",
        "apple:wipe",
        "com.apple.iWork.Keynote.BLTBlinds",
        "com.apple.iWork.Keynote.KLNColorPlanes",
        "apple:3D-cube",
        "apple:doorway",
        "apple:fall",
        "apple:revolve",
        "com.apple.iWork.Keynote.BUKFlop",
        "com.apple.iWork.Keynote.BLTMosaicFlip",
        "apple:pageflip",
        "apple:pivot",
        "com.apple.iWork.Keynote.BLTReflection",
        "com.apple.iWork.Keynote.BLTRevolvingDoor",
        "apple:scale",
        "com.apple.iWork.Keynote.KLNSwap",
        "com.apple.iWork.Keynote.BLTSwoosh",
        "apple:twirl",
        "com.apple.iWork.Keynote.BUKTwist",
        "apple:ca-cube",
        "apple:ca-dissolve-and-flip",
        "apple:ca-pop",
        "apple:ca-push",
        "apple:ca-revolve",
        "apple:ca-zoom",
        "apple:ca-isometric",
        "apple:ca-text-shimmer",
        "apple:ca-text-sparkle",
        "apple:ca-swing",
    ]

    /// Element build-in effects (kind "In").
    public static let buildIns: [String] = [
        "apple:bc-appear",
        "com.apple.iWork.Keynote.Blur",
        "apple:bc-expand",
        "apple:dissolve character",
        "apple:drift",
        "apple:drift and scale character",
        "apple:bc-drop",
        "apple:fade and move character",
        "com.apple.iWork.Keynote.FromDarkness",
        "apple:sidezoom",
        "apple:wipe-iris",
        "apple:keyboard",
        "apple:move in character",
        "apple:wipe",
        "com.apple.iWork.Keynote.BLTBlinds",
        "apple:bc-3D-cube",
        "apple:bc-flip",
        "apple:bc-orbital",
        "apple:pivot-build",
        "apple:bc-pop",
        "apple:zoom character",
        "apple:bc-zoom-big character",
        "apple:bc-superflip",
        "com.apple.iWork.Keynote.BLTSwoosh",
        "apple:spin",
        "apple:twist-and-scale",
        "com.apple.iWork.Keynote.BUKAnvil",
        "com.apple.iWork.Keynote.KLNBCBlast",
        "com.apple.iWork.Keynote.KLNBouncy",
        "com.apple.iWork.Keynote.KLNComet",
        "com.apple.iWork.Keynote.KLNConfetti",
        "com.apple.iWork.Keynote.KNFireworks",
        "com.apple.iWork.Keynote.KLNFlame",
        "com.apple.iWork.Keynote.BUKFlashBulbs",
        "com.apple.iWork.Keynote.BUKLensFlare",
        "com.apple.iWork.Keynote.KLNShimmer",
        "com.apple.iWork.Keynote.KNBuildSkidByCharacter",
        "com.apple.iWork.Keynote.KLNSparkle",
        "com.apple.iWork.Keynote.KLNSquish",
        "com.apple.iWork.Keynote.Trace",
    ]

    /// Element build-out effects (kind "Out").
    public static let buildOuts: [String] = [
        "com.apple.iWork.Keynote.Blur",
        "apple:bc-appear",
        "apple:dissolve character",
        "apple:bc-expand",
        "apple:fade and move character",
        "com.apple.iWork.Keynote.FromDarkness",
        "apple:sidezoom",
        "apple:wipe-iris",
        "apple:keyboard",
        "apple:move in character",
        "apple:wipe",
        "com.apple.iWork.Keynote.BLTBlinds",
        "apple:bc-3D-cube",
        "apple:bc-flip",
        "apple:bc-orbital",
        "apple:pivot-build",
        "apple:bc-pop",
        "apple:zoom character",
        "apple:bc-zoom-big character",
        "apple:bc-superflip",
        "com.apple.iWork.Keynote.BLTSwoosh",
        "apple:spin",
        "apple:twist-and-scale",
        "com.apple.iWork.Keynote.KLNBCBlast",
        "com.apple.iWork.Keynote.KLNBouncy",
        "com.apple.iWork.Keynote.KLNComet",
        "com.apple.iWork.Keynote.KLNConfetti",
        "com.apple.iWork.Keynote.Crumble",
        "com.apple.iWork.Keynote.KLNDiffuse",
        "apple:fall-apart",
        "com.apple.iWork.Keynote.KLNFlame",
        "com.apple.iWork.Keynote.BUKFlashBulbs",
        "com.apple.iWork.Keynote.BUKLensFlare",
        "com.apple.iWork.Keynote.KLNShimmer",
        "com.apple.iWork.Keynote.KNBuildSkidByCharacter",
        "com.apple.iWork.Keynote.KLNSparkle",
        "com.apple.iWork.Keynote.KLNSquish",
        "com.apple.iWork.Keynote.Trace",
        "com.apple.iWork.Keynote.Vanish",
    ]

    /// Action builds (kind "Action").
    public static let actions: [String] = [
        "apple:action-motion-path",
        "apple:action-opacity",
        "apple:action-rotation",
        "apple:action-scale",
        "apple:action-blink",
        "apple:action-bounce",
        "apple:action-flip",
        "apple:action-jiggle",
        "apple:action-pop",
        "apple:action-pulse",
    ]
    // Common effects, for discoverability.
    public static let dissolve = "apple:dissolve"
    public static let appear = "apple:bc-appear"
    public static let pop = "apple:bc-pop"
    public static let moveIn = "apple:move in character"
    public static let fadeAndMove = "apple:fade and move character"
    public static let confetti = "com.apple.iWork.Keynote.KLNConfetti"
    public static let magicMove = "apple:magic-move-implied-motion-path"
    public static let push = "apple:push"
    public static let cube = "apple:3D-cube"
    public static let wipe = "apple:wipe"
    public static let fadeThroughColor = "com.apple.iWork.Keynote.BLTFadeThruColor"
}
