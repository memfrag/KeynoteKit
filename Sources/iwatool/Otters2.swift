import Foundation
import KeynoteBuilder
import KeynoteModel

/// A second, editorial take on the otter slideshow: each content slide is a
/// full-height half-bleed photograph beside a solid text panel, split by a thin
/// accent seam, with a big ghosted index numeral. Title/closing slides are
/// centered over a scrimmed full-bleed photo.
enum OtterDeck2 {

    // Palette — deep blue-charcoal with a warm coral accent.
    static let bg = Fill.color(0.055, 0.075, 0.09, 1)         // near-black ink-blue
    static let bgColor = RGBAColor.rgb(0.055, 0.075, 0.09)
    static let coral = RGBAColor.rgb(0.98, 0.55, 0.40)
    static let ink = RGBAColor.rgb(0.95, 0.96, 0.97)          // near-white
    static let muted = RGBAColor.rgb(0.62, 0.67, 0.72)

    struct Photo { let file: String; let aspect: Double }

    static func build(assets: URL, to out: URL) throws {
        let lake = Photo(file: "lake-adam-vradenburg-GA09PKfRIQY-unsplash.jpg", aspect: 1.5)
        let johnny = Photo(file: "otter-johnny-thorpe-n8IOzK96bN4-unsplash.jpg", aspect: 0.667)
        let joshua = Photo(file: "otter-joshua-j-cotten-aaUMGx6YguU-unsplash.jpg", aspect: 1.777)
        let kedar = Photo(file: "otter-kedar-gadge-X9cBHEPO6LU-unsplash.jpg", aspect: 1.5)
        let mana = Photo(file: "otter-mana5280-axqTLZ12Jss-unsplash.jpg", aspect: 1.0)
        let mariola = Photo(file: "otter-mariola-grobelska-HTxbKcrdvoM-unsplash.jpg", aspect: 1.524)
        let ray = Photo(file: "otter-ray-harrington-0yaKFO-_GJM-unsplash.jpg", aspect: 0.891)

        var canvases: [Canvas] = []

        // 1 — Title (centered over a scrimmed full-bleed lake).
        canvases.append(titleSlide(
            photo: lake, kicker: "A FIELD GUIDE TO RIVERS & COASTS",
            title: "Otters", subtitle: "Nature's playful engineers of water"
        ))

        // Content.
        let content: [(kicker: String, title: String, bullets: [String], photo: Photo)] = [
            ("MEET THE OTTER", "Playful by Nature", [
                "Semi-aquatic mammals of the weasel family",
                "Thirteen species, from rivers to open sea",
                "Famous for sliding, wrestling, and play",
            ], joshua),
            ("ANATOMY", "Built for Water", [
                "Webbed feet and a rudder-like tail",
                "The densest fur of any animal",
                "Bodies that twist and dive with ease",
            ], johnny),
            ("DIET", "Master Foragers", [
                "Hunt fish, crabs, urchins, and clams",
                "Sea otters crack shells with stone tools",
                "Eat a quarter of their weight each day",
            ], kedar),
            ("FAMILY LIFE", "Rafts and Pups", [
                "Float together in groups called rafts",
                "Hold hands asleep so they don't drift",
                "Mothers groom pups on their bellies",
            ], mana),
            ("HABITAT", "Rivers to Kelp Forests", [
                "River otters roam freshwater streams",
                "Sea otters live in coastal kelp forests",
                "Found on nearly every continent",
            ], mariola),
            ("ECOLOGY", "A Keystone Species", [
                "They keep urchin populations in check",
                "That protects carbon-storing kelp",
                "Their presence signals a healthy coast",
            ], ray),
            ("CHALLENGES", "Under Pressure", [
                "Once hunted to near extinction for fur",
                "Threatened by pollution and oil spills",
                "Sensitive to falling water quality",
            ], joshua),
            ("THE FUTURE", "A Conservation Story", [
                "Protected populations are recovering",
                "Reintroductions restore kelp coasts",
                "Every clean waterway helps them thrive",
            ], kedar),
        ]

        for (index, slide) in content.enumerated() {
            canvases.append(contentSlide(slide, index: index + 1, imageLeft: index % 2 == 0))
        }

        // 10 — Closing (centered over a scrimmed full-bleed otter).
        canvases.append(titleSlide(
            photo: johnny, kicker: "THANK YOU",
            title: "Keep Water Wild", subtitle: "— for the otters"
        ))

        // Render, then layer on animation (same verified spec as attempt one).
        var document = try CanvasWriter().build(canvases, imageBaseURL: assets)

        let bottomToTop = PushDirection.fromBottom.rawValue
        for index in 0..<document.slideCount {
            try document.setSlideTransition(
                at: index,
                to: SlideTransition(effect: "apple:push", duration: 0.4, direction: bottomToTop)
            )
        }
        for index in 1...content.count {
            guard let bullets = try document.sceneTree(forSlideAt: index).nodes
                .first(where: { $0.label == "bullets" }) else { continue }
            try document.addBuild(
                SlideBuild(
                    nodeID: bullets.id, kind: "In", effect: "apple:fade and move character",
                    duration: 0.3, delivery: BuildDelivery.byParagraph,
                    textDelivery: BuildTextDelivery.byObject, direction: bottomToTop,
                    travelDistance: 0.07
                ),
                toSlideAt: index
            )
        }

        try document.write(to: out)
    }

    /// A centered title/closing slide over a scrimmed full-bleed photo.
    static func titleSlide(photo: Photo, kicker: String, title: String, subtitle: String) -> Canvas {
        Canvas {
            Image(path: photo.file).frame(cover(photo.aspect))
            // Flat scrim + a stronger fade toward the bottom for legibility.
            Shape().frame(x: 0, y: 0, width: 1024, height: 768).fill(.color(0.03, 0.05, 0.06, 0.32))
            Shape().frame(x: 0, y: 300, width: 1024, height: 468)
                .fill(.linearGradient(stops: [
                    GradientStop(color: (0.02, 0.05, 0.06, 0), location: 0),
                    GradientStop(color: (0.02, 0.05, 0.06, 0.75), location: 1),
                ], angleDegrees: 270))
            // Centered coral rule, kicker, title, subtitle.
            Shape().frame(x: 482, y: 292, width: 60, height: 4).fill(coral)
            Text(kicker).frame(x: 112, y: 316, width: 800, height: 34)
                .fontSize(20).bold().foregroundColor(coral).alignment(.center)
            Text(title).frame(x: 62, y: 348, width: 900, height: 150)
                .fontSize(112).bold().foregroundColor(ink).alignment(.center)
            Text(subtitle).frame(x: 112, y: 508, width: 800, height: 50)
                .fontSize(28).italic().foregroundColor(muted).alignment(.center)
        }
        .background(bg)
    }

    /// A content slide: full-height half-bleed photo beside a solid text panel.
    static func contentSlide(
        _ slide: (kicker: String, title: String, bullets: [String], photo: Photo),
        index: Int, imageLeft: Bool
    ) -> Canvas {
        let panelX: Double = imageLeft ? 512 : 0
        let imageBox = Frame(x: imageLeft ? 0 : 512, y: 0, width: 512, height: 768)
        let textX = panelX + 64
        let number = String(format: "%02d", index)
        return Canvas {
            // Photo, then an opaque panel that both holds the text and masks the
            // photo's overflow into the panel half.
            Image(path: slide.photo.file).frame(coverBox(slide.photo.aspect, imageBox))
            Shape().frame(x: panelX, y: 0, width: 512, height: 768).fill(bgColor)
            // Thin accent seam along the split.
            Shape().frame(x: 510, y: 0, width: 4, height: 768).fill(coral)
            // Big ghosted index numeral bleeding off the panel's lower corner.
            Text(number)
                .frame(x: imageLeft ? 560 : -40, y: 470, width: 520, height: 340)
                .fontSize(300).bold().foregroundColor(ink).opacity(0.06)
                .alignment(imageLeft ? .left : .right)
            // Content, top-aligned.
            Shape().frame(x: textX, y: 120, width: 48, height: 5).fill(coral)
            Text(slide.kicker).frame(x: textX, y: 150, width: 384, height: 30)
                .fontSize(17).bold().foregroundColor(coral)
            Text(slide.title).frame(x: textX, y: 184, width: 400, height: 130)
                .fontSize(44).bold().foregroundColor(ink)
            Text(slide.bullets.joined(separator: "\n"))
                .frame(x: textX, y: 340, width: 392, height: 320)
                .fontSize(23).foregroundColor(ink)
                .bulleted(color: ink)
                .name("bullets")
        }
        .background(bg)
    }

    /// Cover a full 1024×768 slide with a photo, cropping the overflow.
    static func cover(_ aspect: Double) -> Frame { coverBox(aspect, Frame(x: 0, y: 0, width: 1024, height: 768)) }

    /// Scale a photo to cover a box (both dimensions ≥ the box), centered — the
    /// overflow is clipped by the slide edge or hidden by the panel on top.
    static func coverBox(_ aspect: Double, _ box: Frame) -> Frame {
        var w = box.width
        var h = w / aspect
        if h < box.height { h = box.height; w = h * aspect }
        return Frame(x: box.x + (box.width - w) / 2, y: box.y + (box.height - h) / 2, width: w, height: h)
    }
}
