import Foundation
import KeynoteBuilder
import KeynoteModel

/// Builds a modern otter slideshow from the images in an assets folder.
enum OtterDeck {

    // Palette.
    static let bg = Fill.color(0.055, 0.145, 0.16, 1)          // deep teal
    static func aqua(_ a: Double = 1) -> RGBAColor { .rgb(0.30, 0.85, 0.76) }
    static let ink = RGBAColor.rgb(0.93, 0.97, 0.96)           // near-white
    static let muted = RGBAColor.rgb(0.55, 0.70, 0.70)

    struct Photo { let file: String; let aspect: Double }

    static func build(assets: URL, to out: URL) throws {
        // Known image aspect ratios (w/h) from the assets.
        let lake = Photo(file: "lake-adam-vradenburg-GA09PKfRIQY-unsplash.jpg", aspect: 1.5)
        let johnny = Photo(file: "otter-johnny-thorpe-n8IOzK96bN4-unsplash.jpg", aspect: 0.667)
        let joshua = Photo(file: "otter-joshua-j-cotten-aaUMGx6YguU-unsplash.jpg", aspect: 1.777)
        let kedar = Photo(file: "otter-kedar-gadge-X9cBHEPO6LU-unsplash.jpg", aspect: 1.5)
        let mana = Photo(file: "otter-mana5280-axqTLZ12Jss-unsplash.jpg", aspect: 1.0)
        let mariola = Photo(file: "otter-mariola-grobelska-HTxbKcrdvoM-unsplash.jpg", aspect: 1.524)
        let ray = Photo(file: "otter-ray-harrington-0yaKFO-_GJM-unsplash.jpg", aspect: 0.891)

        var canvases: [Canvas] = []

        // 1 — Intro (full-bleed lake + gradient + big title).
        canvases.append(Canvas {
            Image(path: lake.file).frame(cover(lake.aspect))
            Shape().frame(x: 0, y: 300, width: 1024, height: 468)
                .fill(.linearGradient(stops: [
                    GradientStop(color: (0.02, 0.07, 0.08, 0), location: 0),
                    GradientStop(color: (0.02, 0.07, 0.08, 0.92), location: 1),
                ], angleDegrees: 270))
            Text("A FIELD GUIDE").frame(x: 70, y: 470, width: 700, height: 40)
                .fontSize(20).bold().foregroundColor(aqua())
            Text("Otters").frame(x: 64, y: 500, width: 900, height: 150)
                .fontSize(104).bold().foregroundColor(ink)
            Text("Nature's playful engineers of river and coast")
                .frame(x: 70, y: 650, width: 860, height: 60)
                .fontSize(28).italic().foregroundColor(muted)
        })

        // Content slides.
        let content: [(kicker: String, title: String, bullets: [String], photo: Photo)] = [
            ("01 · MEET THE OTTER", "Playful by Nature", [
                "Semi-aquatic mammals of the weasel family",
                "Thirteen species, from rivers to open sea",
                "Famous for sliding, wrestling, and play",
            ], joshua),
            ("02 · ANATOMY", "Built for Water", [
                "Webbed feet and a rudder-like tail",
                "The densest fur of any animal — up to a million hairs per square inch",
                "Streamlined bodies that twist and dive with ease",
            ], mana),
            ("03 · DIET", "Master Foragers", [
                "Hunt fish, crabs, urchins, and clams",
                "Sea otters use rocks as tools to crack shells",
                "Eat up to a quarter of their body weight daily",
            ], kedar),
            ("04 · FAMILY LIFE", "Rafts and Pups", [
                "Float together in groups called rafts",
                "Hold hands while sleeping so they don't drift apart",
                "Mothers carry and groom pups on their bellies",
            ], mariola),
            ("05 · HABITAT", "Rivers to Kelp Forests", [
                "River otters roam freshwater streams and lakes",
                "Sea otters live among coastal kelp forests",
                "Found across the Americas, Europe, Asia, and Africa",
            ], johnny),
            ("06 · ECOLOGY", "A Keystone Species", [
                "Sea otters keep urchin populations in check",
                "That protects kelp forests, which store carbon",
                "Their presence signals a healthy ecosystem",
            ], ray),
            ("07 · CHALLENGES", "Under Pressure", [
                "Once hunted to near extinction for their fur",
                "Threatened by pollution, oil spills, and habitat loss",
                "Sensitive to changes in water quality",
            ], kedar),
            ("08 · THE FUTURE", "A Conservation Story", [
                "Protected populations are slowly recovering",
                "Reintroduction programs are restoring kelp coasts",
                "Every clean waterway helps otters thrive",
            ], joshua),
        ]

        for (index, slide) in content.enumerated() {
            let imageLeft = index % 2 == 1
            canvases.append(contentSlide(slide, imageLeft: imageLeft))
        }

        // 10 — Exit (full-bleed otter + gradient + thanks).
        canvases.append(Canvas {
            Image(path: mariola.file).frame(cover(mariola.aspect))
            Shape().frame(x: 0, y: 0, width: 1024, height: 768)
                .fill(.linearGradient(stops: [
                    GradientStop(color: (0.02, 0.07, 0.08, 0.15), location: 0),
                    GradientStop(color: (0.02, 0.07, 0.08, 0.85), location: 1),
                ], angleDegrees: 270))
            Text("Thank You").frame(x: 64, y: 300, width: 900, height: 140)
                .fontSize(84).bold().foregroundColor(ink)
            Text("Keep our waters wild — for the otters")
                .frame(x: 70, y: 450, width: 860, height: 60)
                .fontSize(28).italic().foregroundColor(aqua())
        })

        // Render, then layer on the animation.
        var document = try CanvasWriter().build(canvases, imageBaseURL: assets)

        // Push from the bottom (content travels bottom → top).
        let bottomToTop = PushDirection.fromBottom.rawValue

        for index in 0..<document.slideCount {
            try document.setSlideTransition(
                at: index,
                to: SlideTransition(effect: "apple:push", duration: 0.4, direction: bottomToTop)
            )
        }
        // "Fade and Move" build-in on each content slide's bullets. The real
        // effect identifier is "apple:fade and move character" (with spaces) —
        // "apple:fade-and-move" silently renders as Dissolve. For bulleted text
        // the "By Bullet" UI option is stored as delivery "By Paragraph".
        for index in 1...content.count {
            guard let bullets = try document.sceneTree(forSlideAt: index).nodes.first(where: { $0.label == "bullets" })
            else { continue }
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

    /// A split content slide: title + bullets on one side, photo on the other.
    static func contentSlide(
        _ slide: (kicker: String, title: String, bullets: [String], photo: Photo), imageLeft: Bool
    ) -> Canvas {
        let textX: Double = imageLeft ? 520 : 70
        let photoBox = Frame(x: imageLeft ? 64 : 560, y: 110, width: 400, height: 548)
        let photoFrame = fit(slide.photo.aspect, in: photoBox)
        return Canvas {
            // Accent tab.
            Shape().frame(x: textX, y: 96, width: 44, height: 6).fill(.rgb(0.30, 0.85, 0.76))
            Text(slide.kicker).frame(x: textX, y: 116, width: 420, height: 30)
                .fontSize(17).bold().foregroundColor(aqua())
            Text(slide.title).frame(x: textX, y: 146, width: 430, height: 130)
                .fontSize(46).bold().foregroundColor(ink)
            Text(slide.bullets.joined(separator: "\n"))
                .frame(x: textX, y: 300, width: 430, height: 340)
                .fontSize(24).foregroundColor(ink)
                .bulleted(color: ink)
                .name("bullets")
            Image(path: slide.photo.file).frame(photoFrame)
                .mask(.roundedRectangle(cornerRadius: 22))
                .shadow(color: .black, offset: 6, blur: 18, opacity: 0.5)
        }
        .background(bg)
    }

    /// Aspect-fit a photo inside a box, centered.
    static func fit(_ aspect: Double, in box: Frame) -> Frame {
        var w = box.width, h = box.height
        if aspect > box.width / box.height { h = w / aspect } else { w = h * aspect }
        return Frame(x: box.x + (box.width - w) / 2, y: box.y + (box.height - h) / 2, width: w, height: h)
    }

    /// Cover the whole 1024×768 slide with a photo, cropping the overflow.
    static func cover(_ aspect: Double) -> Frame {
        let slideW = 1024.0, slideH = 768.0
        var w = slideW, h = slideW / aspect
        if h < slideH { h = slideH; w = slideH * aspect }
        return Frame(x: (slideW - w) / 2, y: (slideH - h) / 2, width: w, height: h)
    }
}
