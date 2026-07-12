import Foundation
import IWAContainer
import KeynoteBuilder
import KeynoteModel

let usage = """
usage:
  iwatool info <file.key>                        list entries, records per .iwa component
  iwatool roundtrip <in.key> <out.key>           unpack, re-encode every .iwa, repack
  iwatool text <file.key>                        print all text storages
  iwatool dump <file.key> <component-path>       print records as protobuf text format
  iwatool replace <in.key> <out.key> <find> <replacement>
                                                 replace text across the document
  iwatool duplicate-slide <in.key> <out.key> <index>   duplicate slide (0-based)
  iwatool remove-slide <in.key> <out.key> <index>      remove slide (0-based)
  iwatool move-slide <in.key> <out.key> <from> <to>    reorder slides (0-based)
  iwatool replace-image <in.key> <out.key> <name> <image-file>
                                                 replace an image (by original file name)
  iwatool list-media <file.key>                  list Data/ files
  iwatool set-text <in.key> <out.key> <node-id> <text>      set a node's text
  iwatool set-frame <in.key> <out.key> <node-id> <x> <y> <w> <h>  move/resize a node
  iwatool set-media <in.key> <out.key> <node-id> <image-file>     replace a node's image
  iwatool delete-node <in.key> <out.key> <node-id>          delete a free drawable
  iwatool clone-node <in.key> <out.key> <node-id> <slide-index>   clone a drawable onto a slide
  iwatool set-cell <in.key> <out.key> <node-id> <row> <col> <value>
                                                 set a table cell (numeric value -> number cell)
  iwatool set-transition <in.key> <out.key> <slide-index> <effect> [duration]
                                                 set a slide transition (e.g. apple:dissolve;
                                                 "none" removes it)
  iwatool builds <file.key> <slide-index>        list a slide's element builds
  iwatool effects [transitions|build-ins|build-outs|actions]
                                                 list known-good effect identifiers
  iwatool add-build <in.key> <out.key> <slide-index> <node-id> <In|Out> <effect> [duration]
  iwatool remove-build <in.key> <out.key> <slide-index> <build-id>
  iwatool apply-tree <in.key> <out.key> <tree.json>         apply an edited scene tree
                                                 (node ids come from 'iwatool tree')
  iwatool build <outline.txt> <out.key>          build a deck from a simple outline
  iwatool build-md <slides.md> <out.key> [template.key]
                                                 build a deck from a markdown presentation,
                                                 optionally using a multi-layout template
  iwatool build-json <spec.json> <out.key>       build a deck from a declarative JSON spec
  iwatool set-title <in.key> <out.key> <index> <text>   set a slide's title
  iwatool describe-template <file.key>           JSON: each slide's layout tag, master, and
                                                 fillable placeholders (role/kind/prompt/frame)
  iwatool tree <file.key> [slide-index]          JSON scene tree: every node (placeholder,
                                                 image, shape, group...) with id/role/text/
                                                 frame/media, z-ordered
  iwatool blocks-of <file.key> <slide-index>     list a slide's fillable text blocks
                                                 (the keys the builder DSL's `blocks` accepts)
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

let arguments = CommandLine.arguments

if arguments.count >= 4, arguments[1] == "otters" {
    let assets = URL(fileURLWithPath: arguments[2], isDirectory: true)
    let out = URL(fileURLWithPath: arguments[3])
    try OtterDeck.build(assets: assets, to: out)
    print("otter slideshow written to \(out.path)"); exit(0)
}

if arguments.count >= 4, arguments[1] == "otters2" {
    let assets = URL(fileURLWithPath: arguments[2], isDirectory: true)
    let out = URL(fileURLWithPath: arguments[3])
    try OtterDeck2.build(assets: assets, to: out)
    print("otter slideshow (v2) written to \(out.path)"); exit(0)
}

if arguments.count >= 3, arguments[1] == "custom-path-demo" {
    let out = URL(fileURLWithPath: arguments[2])
    // A heart, drawn in a 100x90 space with two cubic curves.
    let heart = BezierPath()
        .move(to: 50, 90)
        .curve(to: 0, 35, control1: (35, 75), control2: (0, 58))
        .curve(to: 50, 22, control1: (0, 8), control2: (38, 2))
        .curve(to: 100, 35, control1: (62, 2), control2: (100, 8))
        .curve(to: 50, 90, control1: (100, 58), control2: (65, 75))
        .close()
    // An arrow (open polygon).
    let arrow = BezierPath()
        .move(to: 0, 30).line(to: 60, 30).line(to: 60, 10).line(to: 100, 50)
        .line(to: 60, 90).line(to: 60, 70).line(to: 0, 70).close()
    let canvas = Canvas {
        Shape(.path(heart)).frame(x: 120, y: 150, width: 300, height: 270).fill(.rgb(0.9, 0.2, 0.35))
        Shape(.path(arrow)).frame(x: 560, y: 180, width: 340, height: 200).fill(.rgb(0.2, 0.55, 0.9))
    }
    try CanvasWriter().write([canvas], to: out)
    print("custom path demo written"); exit(0)
}

if arguments.count >= 4, arguments[1] == "textflip-test" {
    let paletteIn = URL(fileURLWithPath: arguments[2])
    let out = URL(fileURLWithPath: arguments[3])
    var document = try KeynoteDocument(contentsOf: paletteIn)
    let a = try document.addText(toSlideAt: 0, string: "Flip me", frame: Frame(x: 120, y: 150, width: 500, height: 120))
    try document.setNodeCharacterStyle(a, fontSize: 60, bold: true)
    let b = try document.addText(toSlideAt: 0, string: "Flip me", frame: Frame(x: 120, y: 350, width: 500, height: 120))
    try document.setNodeCharacterStyle(b, fontSize: 60, bold: true, color: (0.9,0.3,0.35,1))
    try document.setNodeFlip(b, horizontal: true)
    try document.write(to: out)
    print("textflip written"); exit(0)
}

if arguments.count >= 4, arguments[1] == "parastyle-test" {
    let paletteIn = URL(fileURLWithPath: arguments[2])
    let out = URL(fileURLWithPath: arguments[3])
    var document = try KeynoteDocument(contentsOf: paletteIn)
    let heading = try document.defineParagraphStyle(ParagraphStyle(
        name: "Big Heading", fontSize: 54, bold: true, color: (0.15, 0.35, 0.8, 1), alignment: .center
    ))
    let body = try document.defineParagraphStyle(ParagraphStyle(
        name: "Callout Body", fontSize: 26, italic: true, color: (0.3, 0.3, 0.3, 1),
        alignment: .right, spaceBefore: 6, spaceAfter: 6, background: (0.95, 0.9, 0.7, 1)
    ))
    let t1 = try document.addText(toSlideAt: 0, string: "Centered heading", frame: Frame(x: 80, y: 120, width: 860, height: 120))
    try document.applyParagraphStyle(heading, to: t1)
    let t2 = try document.addText(toSlideAt: 0, string: "Right-aligned body text\non two lines", frame: Frame(x: 80, y: 300, width: 860, height: 160))
    try document.applyParagraphStyle(body, to: t2)
    // Columns + inset on a longer text box.
    let t3 = try document.addText(toSlideAt: 0, string: "This paragraph flows across two columns with an inset from the box edge, wrapping as it goes so both columns fill with text and you can see the column gap between them.", frame: Frame(x: 80, y: 500, width: 860, height: 220))
    try document.setNodeCharacterStyle(t3, fontSize: 22)
    try document.setNodeColumns(t3, count: 2, gap: 40)
    try document.setNodeTextInset(t3, 20)
    try document.write(to: out)
    print("parastyle test written"); exit(0)
}

if arguments.count >= 4, arguments[1] == "tabborder-test" {
    let paletteIn = URL(fileURLWithPath: arguments[2])
    let out = URL(fileURLWithPath: arguments[3])
    var document = try KeynoteDocument(contentsOf: paletteIn)
    let boxed = try document.defineParagraphStyle(ParagraphStyle(
        name: "Boxed", fontSize: 34, color: (0.1,0.1,0.1,1), alignment: .center,
        spaceBefore: 10, spaceAfter: 10, background: (0.93,0.96,1,1)
    ))
    let b = try document.addText(toSlideAt: 0, string: "Bordered paragraph", frame: Frame(x: 120, y: 160, width: 780, height: 120))
    try document.applyParagraphStyle(boxed, to: b)
    let tabbed = try document.defineParagraphStyle(ParagraphStyle(
        name: "Tabbed", fontSize: 30, alignment: .left,
        tabs: [TabStop(position: 400, alignment: .left, leader: "."), TabStop(position: 740, alignment: .right)]
    ))
    let tt = try document.addText(toSlideAt: 0, string: "Item one\t$10\nItem two\t$4\nGrand total\t$14", frame: Frame(x: 120, y: 360, width: 780, height: 250))
    try document.applyParagraphStyle(tabbed, to: tt)
    try document.write(to: out)
    print("tabborder test written"); exit(0)
}

if arguments.count >= 4, arguments[1] == "dropcap-test" {
    let paletteIn = URL(fileURLWithPath: arguments[2])
    let out = URL(fileURLWithPath: arguments[3])
    var document = try KeynoteDocument(contentsOf: paletteIn)
    let t = try document.addText(toSlideAt: 0, string: "Once upon a time there was a paragraph that began with a large decorative drop cap spanning several lines of text as is traditional in fine typography and books.", frame: Frame(x: 120, y: 160, width: 780, height: 360))
    try document.setNodeCharacterStyle(t, fontSize: 30)
    try document.setNodeDropCap(t, lines: 3, characters: 1)
    try document.write(to: out)
    print("dropcap test written"); exit(0)
}

if arguments.count >= 4, arguments[1] == "textextra-test" {
    let paletteIn = URL(fileURLWithPath: arguments[2])
    let out = URL(fileURLWithPath: arguments[3])
    var document = try KeynoteDocument(contentsOf: paletteIn)
    let u = try document.addText(toSlideAt: 0, string: "Underlined text", frame: Frame(x: 120, y: 140, width: 780, height: 90))
    try document.setNodeCharacterStyle(u, fontSize: 40, underline: true)
    let s = try document.addText(toSlideAt: 0, string: "Struck-through text", frame: Frame(x: 120, y: 260, width: 780, height: 90))
    try document.setNodeCharacterStyle(s, fontSize: 40, strikethrough: true)
    let sp = try document.defineParagraphStyle(ParagraphStyle(name: "Loose", fontSize: 30, lineSpacing: 2.0))
    let l = try document.addText(toSlideAt: 0, string: "Line one with wide spacing\nLine two with wide spacing\nLine three", frame: Frame(x: 120, y: 380, width: 780, height: 260))
    try document.applyParagraphStyle(sp, to: l)
    try document.write(to: out)
    print("textextra test written"); exit(0)
}

if arguments.count >= 4, arguments[1] == "builddelivery-test" {
    let paletteIn = URL(fileURLWithPath: arguments[2])
    let out = URL(fileURLWithPath: arguments[3])
    var document = try KeynoteDocument(contentsOf: paletteIn)
    let a = try document.addShape(toSlideAt: 0, frame: Frame(x: 100, y: 120, width: 200, height: 160), kind: .native(.star(points: 5, innerRatio: 0.42)))
    try document.setNodeFill(a, to: (0.95, 0.8, 0.2, 1))
    let b = try document.addText(toSlideAt: 0, string: "First line\nSecond line\nThird line", frame: Frame(x: 400, y: 120, width: 500, height: 200))
    try document.setNodeCharacterStyle(b, fontSize: 40)
    let build1 = try document.addBuild(SlideBuild(nodeID: a, kind: "In", effect: "apple:bc-appear"), toSlideAt: 0)
    let build2 = try document.addBuild(SlideBuild(nodeID: b, kind: "In", effect: "apple:dissolve", delivery: "By Paragraph"), toSlideAt: 0)
    // Reverse the order: text animates before the star.
    try document.reorderBuilds(onSlideAt: 0, order: [build2, build1])
    try document.write(to: out)
    // Read back to confirm.
    let reread = try KeynoteDocument(contentsOf: out)
    let builds = try reread.slideBuilds(at: 0)
    print("builds in order:", builds.map { "\($0.nodeID)/\($0.effect)/delivery=\($0.delivery ?? "-")" }.joined(separator: " | "))
    exit(0)
}

if arguments.count >= 4, arguments[1] == "font-test" {
    let paletteIn = URL(fileURLWithPath: arguments[2])
    let out = URL(fileURLWithPath: arguments[3])
    var document = try KeynoteDocument(contentsOf: paletteIn)
    let a = try document.addText(toSlideAt: 0, string: "Futura at 80pt", frame: Frame(x: 120, y: 200, width: 1400, height: 140))
    try document.setNodeCharacterStyle(a, fontName: "Futura", fontSize: 80, bold: true)
    let b = try document.addText(toSlideAt: 0, string: "Times New Roman italic", frame: Frame(x: 120, y: 400, width: 1400, height: 140))
    try document.setNodeCharacterStyle(b, fontName: "Times New Roman", fontSize: 80, italic: true)
    let styled = try document.defineParagraphStyle(ParagraphStyle(name: "Mono", font: "Menlo", fontSize: 60, color: (0.2, 0.4, 0.9, 1)))
    let c = try document.addText(toSlideAt: 0, string: "Menlo via paragraph style", frame: Frame(x: 120, y: 620, width: 1400, height: 140))
    try document.applyParagraphStyle(styled, to: c)
    try document.write(to: out)
    print("font test written; nodes \(a),\(b),\(c)"); exit(0)
}

if arguments.count >= 4, arguments[1] == "bullet-test" {
    let paletteIn = URL(fileURLWithPath: arguments[2])
    let out = URL(fileURLWithPath: arguments[3])
    var document = try KeynoteDocument(contentsOf: paletteIn)
    let n = try document.addText(toSlideAt: 0, string: "Alpha item\nBeta item\nGamma item", frame: Frame(x: 100, y: 180, width: 820, height: 300))
    try document.setNodeCharacterStyle(n, fontSize: 40)
    try document.setNodeNumbered(n, .decimal)
    try document.write(to: out)
    print("bullet test written"); exit(0)
}

if arguments.count >= 5, arguments[1] == "mask-test" {
    let paletteIn = URL(fileURLWithPath: arguments[2])
    let out = URL(fileURLWithPath: arguments[3])
    let png = try Data(contentsOf: URL(fileURLWithPath: arguments[4]))
    var document = try KeynoteDocument(contentsOf: paletteIn)
    let a = try document.addImage(toSlideAt: 0, data: png, frame: Frame(x: 80, y: 120, width: 260, height: 260))
    try document.maskImage(a, with: .ellipse)
    let b = try document.addImage(toSlideAt: 0, data: png, frame: Frame(x: 400, y: 120, width: 260, height: 260))
    try document.maskImage(b, with: .native(.star(points: 5, innerRatio: 0.45)))
    let c = try document.addImage(toSlideAt: 0, data: png, frame: Frame(x: 720, y: 120, width: 260, height: 260))
    try document.maskImage(c, with: .roundedRectangle(cornerRadius: 60))
    try document.write(to: out)
    print("mask test written"); exit(0)
}

if arguments.count >= 5, arguments[1] == "flip-test" {
    let paletteIn = URL(fileURLWithPath: arguments[2])
    let out = URL(fileURLWithPath: arguments[3])
    let fpng = try Data(contentsOf: URL(fileURLWithPath: arguments[4]))
    var document = try KeynoteDocument(contentsOf: paletteIn)
    let n = try document.addImage(toSlideAt: 0, data: fpng, frame: Frame(x: 60, y: 120, width: 200, height: 200))
    let h = try document.addImage(toSlideAt: 0, data: fpng, frame: Frame(x: 320, y: 120, width: 200, height: 200))
    try document.setNodeFlip(h, horizontal: true)
    let v = try document.addImage(toSlideAt: 0, data: fpng, frame: Frame(x: 580, y: 120, width: 200, height: 200))
    try document.setNodeFlip(v, vertical: true)
    // A shape flipped horizontally (was path-source; now geometry flags).
    let s = try document.addShape(toSlideAt: 0, frame: Frame(x: 320, y: 420, width: 300, height: 140), kind: .native(.rightArrow))
    try document.setNodeFill(s, to: (0.9, 0.3, 0.35, 1))
    try document.setNodeFlip(s, horizontal: true)
    try document.write(to: out)
    print("flip test: normal=\(n) h=\(h) v=\(v) shape=\(s)"); exit(0)
}

if arguments.count >= 4, arguments[1] == "group-demo" {
    let paletteIn = URL(fileURLWithPath: arguments[2])
    let out = URL(fileURLWithPath: arguments[3])
    var document = try KeynoteDocument(contentsOf: paletteIn)
    let a = try document.addShape(toSlideAt: 0, frame: Frame(x: 100, y: 120, width: 160, height: 160), kind: .native(.star(points: 5, innerRatio: 0.42)))
    try document.setNodeFill(a, to: (0.95, 0.8, 0.2, 1))
    let b = try document.addShape(toSlideAt: 0, frame: Frame(x: 300, y: 120, width: 160, height: 160), kind: .ellipse)
    try document.setNodeFill(b, to: (0.2, 0.5, 0.95, 1))
    // Group the star + ellipse.
    let inner = try document.groupNodes([a, b], onSlideAt: 0)
    // A third shape, then nest: group the group with it.
    let c = try document.addShape(toSlideAt: 0, frame: Frame(x: 200, y: 340, width: 160, height: 160), kind: .native(.plus))
    try document.setNodeFill(c, to: (0.9, 0.3, 0.35, 1))
    let outer = try document.groupNodes([inner, c], onSlideAt: 0)
    try document.write(to: out)
    print("group demo written; inner=\(inner) outer=\(outer)"); exit(0)
}

if arguments.count >= 3, arguments[1] == "arrows-demo" {
    let out = URL(fileURLWithPath: arguments[2])
    let canvas = Canvas {
        Shape(.native(.leftArrow)).frame(x: 100, y: 80, width: 380, height: 140).fill(.rgb(0.15, 0.7, 0.5))
        Shape(.native(.rightArrow)).frame(x: 540, y: 80, width: 380, height: 140).fill(.rgb(0.6, 0.35, 0.85))
        Shape(.native(.doubleArrow)).frame(x: 300, y: 320, width: 420, height: 140).fill(.rgb(0.95, 0.55, 0.15))
        // Lines with different caps.
        Shape(.line).frame(x: 120, y: 520, width: 360, height: 0).border(.rgb(0.2, 0.2, 0.2), width: 4).endCap(.filledArrow)
        Shape(.line).frame(x: 560, y: 520, width: 360, height: 0).border(.rgb(0.2, 0.5, 0.95), width: 4)
            .startCap(.filledCircle).endCap(.diamond)
        // Lines with different stroke styles.
        Shape(.line).frame(x: 120, y: 620, width: 360, height: 0).border(.rgb(0.2, 0.2, 0.2), width: 4, dash: [6, 6])
        Shape(.line).frame(x: 560, y: 620, width: 360, height: 0).border(.dotted(color: (0.9, 0.3, 0.35, 1), width: 6))
    }
    try CanvasWriter().write([canvas], to: out)
    print("arrows demo written"); exit(0)
}

if arguments.count >= 3, arguments[1] == "shapes-demo" {
    let out = URL(fileURLWithPath: arguments[2])
    let kinds: [(ShapeKind, RGBAColor)] = [
        // Top row: bezier shapes. Bottom row: native parametric equivalents.
        (.roundedRectangle(cornerRadius: 50), .rgb(0.15, 0.7, 0.5)),
        (.regularPolygon(sides: 5), .rgb(0.6, 0.35, 0.85)),
        (.star(points: 5, innerRatio: 0.42), .rgb(0.95, 0.8, 0.2)),
        (.native(.roundedRectangle(cornerRadius: 50)), .rgb(0.2, 0.5, 0.95)),
        (.native(.chevron(depth: 0.5)), .rgb(0.95, 0.55, 0.15)),
        (.native(.plus), .rgb(0.9, 0.3, 0.35)),
    ]
    var elements: [Element] = []
    for (i, item) in kinds.enumerated() {
        let col = i % 3, row = i / 3
        elements.append(
            Shape(item.0)
                .frame(x: 90 + Double(col) * 300, y: 120 + Double(row) * 300, width: 220, height: 220)
                .fill(item.1)
        )
    }
    let canvas = Canvas(elements: elements)
    try CanvasWriter().write([canvas], to: out)
    print("shapes demo written"); exit(0)
}

if arguments.count >= 3, arguments[1] == "canvas-demo" {
    let out = URL(fileURLWithPath: arguments[2])
    let imageBase = arguments.count >= 4 ? URL(fileURLWithPath: arguments[3]) : nil
    let canvas = Canvas {
        Text("Composed with a DSL")
            .frame(x: 60, y: 60, width: 840, height: 120)
            .fontSize(54).bold().foregroundColor(.rgb(0.2, 0.5, 0.95))
        Text("Every element is placed by hand")
            .frame(x: 60, y: 190, width: 840, height: 80)
            .fontSize(28).italic().foregroundColor(.rgb(0.75, 0.78, 0.85))
        Shape()
            .frame(x: 60, y: 300, width: 360, height: 260)
            .fill(.linearGradient(stops: [
                GradientStop(color: (0.95, 0.55, 0.15, 1), location: 0),
                GradientStop(color: (0.6, 0.1, 0.35, 1), location: 1),
            ], angleDegrees: 90))
            .border(.white, width: 4)
            .shadow()
            .rotation(degrees: 8)
        if imageBase != nil {
            Image(path: "sun.png")
                .frame(x: 480, y: 300, width: 420, height: 260)
                .border(.rgb(1, 1, 1), width: 6)
                .shadow(color: .black, offset: 8, blur: 12, opacity: 0.6)
                .opacity(0.6)
        }
    }
    .background(.color(0.1, 0.12, 0.2, 1))
    try CanvasWriter().write([canvas], to: out, imageBaseURL: imageBase)
    print("canvas demo written"); exit(0)
}

if arguments.count >= 4, arguments[1] == "synth-shape" {
    // Prove from-scratch drawable synthesis: no clone, just a built shape.
    let paletteIn = URL(fileURLWithPath: arguments[2])
    let out = URL(fileURLWithPath: arguments[3])
    var document = try KeynoteDocument(contentsOf: paletteIn)
    let id = try document.addShape(toSlideAt: 0, frame: Frame(x: 120, y: 120, width: 500, height: 320))
    try document.setNodeFill(id, to: (0.2, 0.7, 0.4, 1))
    try document.write(to: out)
    print("synthesized shape id \(id)"); exit(0)
}

if arguments.count >= 5, arguments[1] == "synth-image" {
    let paletteIn = URL(fileURLWithPath: arguments[2])
    let out = URL(fileURLWithPath: arguments[3])
    let imagePath = URL(fileURLWithPath: arguments[4])
    var document = try KeynoteDocument(contentsOf: paletteIn)
    let id = try document.addImage(
        toSlideAt: 0,
        data: try Data(contentsOf: imagePath),
        frame: Frame(x: 120, y: 120, width: 500, height: 320)
    )
    try document.write(to: out)
    print("synthesized image id \(id)"); exit(0)
}

if arguments.count >= 7, arguments[1] == "set-bg" {
    let input = URL(fileURLWithPath: arguments[2])
    let out = URL(fileURLWithPath: arguments[3])
    let r = Double(arguments[4])!, g = Double(arguments[5])!, b = Double(arguments[6])!
    var document = try KeynoteDocument(contentsOf: input)
    try document.setSlideBackground(at: 0, to: (r, g, b, 1))
    try document.write(to: out)
    print("background set"); exit(0)
}

if arguments.count >= 4, arguments[1] == "set-bg-fill" {
    // set-bg-fill <in> <out> <kind> [imagePath]
    let input = URL(fileURLWithPath: arguments[2])
    let out = URL(fileURLWithPath: arguments[3])
    let kind = arguments.count >= 5 ? arguments[4] : "linear"
    var document = try KeynoteDocument(contentsOf: input)
    let fill: Fill
    switch kind {
    case "none": fill = .none
    case "linear":
        fill = .linearGradient(stops: [
            GradientStop(color: (0.1, 0.2, 0.6, 1), location: 0),
            GradientStop(color: (0.7, 0.2, 0.5, 1), location: 1),
        ], angleDegrees: 90)
    case "radial":
        fill = .radialGradient(stops: [
            GradientStop(color: (0.95, 0.85, 0.3, 1), location: 0),
            GradientStop(color: (0.6, 0.1, 0.2, 1), location: 1),
        ])
    case "image":
        let path = URL(fileURLWithPath: arguments[5])
        fill = .image(try Data(contentsOf: path), mode: .scaleToFill)
    default: fatalError("unknown fill kind")
    }
    try document.setSlideBackground(at: 0, fill: fill)
    try document.write(to: out)
    print("bg fill \(kind) set"); exit(0)
}

if arguments.count >= 4, arguments[1] == "synth-text" {
    let paletteIn = URL(fileURLWithPath: arguments[2])
    let out = URL(fileURLWithPath: arguments[3])
    var document = try KeynoteDocument(contentsOf: paletteIn)
    let id = try document.addText(
        toSlideAt: 0, string: "Synthesized from scratch",
        frame: Frame(x: 120, y: 120, width: 700, height: 120)
    )
    try document.setNodeCharacterStyle(id, fontSize: 44, bold: true, color: (0.15, 0.35, 0.8, 1))
    try document.write(to: out)
    print("synthesized text id \(id)"); exit(0)
}

// Commands that take no input file.
if arguments.count >= 2, arguments[1] == "effects" {
    let lists: [(String, [String])] = [
        ("transitions", KeynoteEffects.transitions),
        ("build-ins", KeynoteEffects.buildIns),
        ("build-outs", KeynoteEffects.buildOuts),
        ("actions", KeynoteEffects.actions),
    ]
    let filter = arguments.count >= 3 ? arguments[2] : nil
    for (name, identifiers) in lists where filter == nil || filter == name {
        print("# \(name)")
        for identifier in identifiers {
            print(identifier)
        }
    }
    exit(0)
}

guard arguments.count >= 3 else { fail(usage) }

let command = arguments[1]
let inputURL = URL(fileURLWithPath: arguments[2])

switch command {
case "set-fill":
    guard arguments.count >= 8, let nodeID = UInt64(arguments[4]),
          let r = Double(arguments[5]), let g = Double(arguments[6]), let b = Double(arguments[7]) else { fail(usage) }
    let outputURL = URL(fileURLWithPath: arguments[3])
    var document = try KeynoteDocument(contentsOf: inputURL)
    try document.setNodeFill(nodeID, to: (r, g, b, 1))
    try document.write(to: outputURL)
    print("set fill on node \(nodeID)")

case "set-char-style":
    guard arguments.count >= 6, let nodeID = UInt64(arguments[4]), let size = Double(arguments[5]) else { fail(usage) }
    let outputURL = URL(fileURLWithPath: arguments[3])
    var document = try KeynoteDocument(contentsOf: inputURL)
    var color: (Double, Double, Double, Double)? = nil
    if arguments.count >= 9, let r = Double(arguments[6]), let g = Double(arguments[7]), let b = Double(arguments[8]) {
        color = (r, g, b, 1)
    }
    try document.setNodeCharacterStyle(nodeID, fontSize: size, bold: true, color: color)
    try document.write(to: outputURL)
    print("set char style on node \(nodeID)")

case "info":
    let archive = try KeyArchive.read(from: inputURL)
    for entry in archive.entries {
        if entry.isIWA {
            let decompressed = try IWA.decompress(entry.data)
            let file = try IWAFile.parse(decompressed)
            let types = file.records.compactMap(\.messageTypes.first)
            print("\(entry.path): \(entry.data.count) bytes compressed, \(decompressed.count) decompressed, \(file.records.count) records, types \(Set(types).sorted())")
        } else {
            print("\(entry.path): \(entry.data.count) bytes")
        }
    }

case "roundtrip":
    guard arguments.count >= 4 else { fail(usage) }
    let outputURL = URL(fileURLWithPath: arguments[3])
    var archive = try KeyArchive.read(from: inputURL)
    for entry in archive.iwaEntries {
        let decompressed = try IWA.decompress(entry.data)
        let file = try IWAFile.parse(decompressed)
        let reserialized = file.serialize()
        guard reserialized == decompressed else {
            fail("record framing not byte-stable for \(entry.path)")
        }
        archive.replaceEntry(at: entry.path, with: IWA.compress(reserialized))
    }
    try archive.write(to: outputURL)

    // Verify: decompressed payloads of the output must match the input.
    let inArchive = try KeyArchive.read(from: inputURL)
    let outArchive = try KeyArchive.read(from: outputURL)
    for entry in inArchive.iwaEntries {
        guard let outEntry = outArchive.entry(at: entry.path) else {
            fail("missing entry in output: \(entry.path)")
        }
        let original = try IWA.decompress(entry.data)
        let rebuilt = try IWA.decompress(outEntry.data)
        guard original == rebuilt else {
            fail("payload mismatch after roundtrip: \(entry.path)")
        }
    }
    print("roundtrip OK: \(outArchive.entries.count) entries, decompressed payloads identical")

case "dump":
    guard arguments.count >= 4 else { fail(usage) }
    let document = try KeynoteDocument(contentsOf: inputURL)
    guard let component = document.components.first(where: { $0.path == arguments[3] }) else {
        fail("no such component; available: \(document.components.map(\.path).joined(separator: ", "))")
    }
    for record in component.records {
        let id = record.identifier.map(String.init) ?? "-"
        for (index, info) in record.info.messageInfos.enumerated() {
            let fieldInfoNote = info.fieldInfos.isEmpty ? "" : " field_infos \(info.fieldInfos.map { "\($0.path.path):refs\($0.objectReferences)" })"
            print("=== id \(id) type \(info.type) v\(info.version) refs \(info.objectReferences)\(fieldInfoNote) ===")
            do {
                let message = try record.decodeMessage(at: index)
                print(message.textFormatString())
            } catch {
                print("<decode failed: \(error)>")
            }
        }
    }

case "cat-iwa":
    guard arguments.count >= 4 else { fail(usage) }
    let archive = try KeyArchive.read(from: inputURL)
    guard let entry = archive.entry(at: arguments[3]) else { fail("no such entry") }
    FileHandle.standardOutput.write(try IWA.decompress(entry.data))

case "text":
    let document = try KeynoteDocument(contentsOf: inputURL)
    for text in TextReplacement.allText(in: document) {
        print(text.replacingOccurrences(of: "\u{2029}", with: "\\n"))
    }

case "replace":
    guard arguments.count >= 6 else { fail(usage) }
    let outputURL = URL(fileURLWithPath: arguments[3])
    var document = try KeynoteDocument(contentsOf: inputURL)
    let count = try TextReplacement.replace(arguments[4], with: arguments[5], in: &document)
    try document.write(to: outputURL)
    print("replaced in \(count) text storage(s)")

case "duplicate-slide", "remove-slide", "move-slide":
    guard arguments.count >= 5 else { fail(usage) }
    let outputURL = URL(fileURLWithPath: arguments[3])
    guard let index = Int(arguments[4]) else { fail(usage) }
    var document = try KeynoteDocument(contentsOf: inputURL)
    switch command {
    case "duplicate-slide":
        let newRootID = try document.duplicateSlide(at: index)
        print("duplicated slide \(index) → new slide root \(newRootID), \(document.slideCount) slides")
    case "remove-slide":
        try document.removeSlide(at: index)
        print("removed slide \(index), \(document.slideCount) slides")
    default:
        guard arguments.count >= 6, let to = Int(arguments[5]) else { fail(usage) }
        try document.moveSlide(from: index, to: to)
        print("moved slide \(index) → \(to)")
    }
    try document.write(to: outputURL)

case "describe-template":
    let document = try KeynoteDocument(contentsOf: inputURL)
    let library = try TemplateLibrary(document: document)
    // Enrich each layout description with its @layout: tag and any layout key
    // that resolves to it, so an AI knows both what the slide is for and how
    // to request it.
    struct DescribedLayout: Encodable {
        let index: Int
        let tag: String?
        let master: String?
        let fields: [KeynoteModel.PlaceholderField]
    }
    let descriptions = try document.layoutDescriptions()
    let tagByIndex = Dictionary(
        library.entries.compactMap { entry in entry.tag.map { (entry.slideIndex, $0) } },
        uniquingKeysWith: { first, _ in first }
    )
    let output = descriptions.map {
        DescribedLayout(index: $0.index, tag: tagByIndex[$0.index], master: $0.masterName, fields: $0.fields)
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(output))
    print()

case "tree":
    let document = try KeynoteDocument(contentsOf: inputURL)
    let trees: [SceneTree]
    if arguments.count >= 4, let slideIndex = Int(arguments[3]) {
        trees = [try document.sceneTree(forSlideAt: slideIndex)]
    } else {
        trees = try document.sceneTrees()
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(trees))
    print()

case "set-block":
    guard arguments.count >= 7, let slideIndex = Int(arguments[4]) else { fail(usage) }
    let outputURL = URL(fileURLWithPath: arguments[3])
    var document = try KeynoteDocument(contentsOf: inputURL)
    try document.setSlideText(at: slideIndex, block: arguments[5], to: arguments[6])
    try document.write(to: outputURL)
    print("set block \"\(arguments[5])\" on slide \(slideIndex)")

case "blocks-of":
    guard arguments.count >= 4, let slideIndex = Int(arguments[3]) else { fail(usage) }
    let document = try KeynoteDocument(contentsOf: inputURL)
    for block in try document.slideTextBlocks(at: slideIndex) {
        let keys = [block.role, block.label, block.text, block.prompt]
            .compactMap { $0 }.filter { !$0.isEmpty }
        print("node \(block.nodeID): \(keys.map { "\"\($0)\"" }.joined(separator: " | "))")
    }

case "set-desc":
    guard arguments.count >= 6, let nodeID = UInt64(arguments[4]) else { fail(usage) }
    let outputURL = URL(fileURLWithPath: arguments[3])
    var document = try KeynoteDocument(contentsOf: inputURL)
    try document.setNodeDescription(nodeID, to: arguments[5])
    try document.write(to: outputURL)
    print("set description of node \(nodeID)")

case "masters":
    let document = try KeynoteDocument(contentsOf: inputURL)
    for i in 0..<document.slideCount {
        let master = (try? document.slideMasterName(at: i)) ?? nil
        let title = (try? document.slideTitle(at: i)) ?? nil
        print("slide \(i): master=\(master ?? "?")  title=\(title ?? "-")")
    }

case "list-media":
    let document = try KeynoteDocument(contentsOf: inputURL)
    for name in document.mediaFileNames {
        print(name)
    }

case "clone-node":
    guard arguments.count >= 6, let nodeID = UInt64(arguments[4]), let slideIndex = Int(arguments[5]) else { fail(usage) }
    let outputURL = URL(fileURLWithPath: arguments[3])
    var document = try KeynoteDocument(contentsOf: inputURL)
    let newID = try document.cloneDrawable(nodeID, toSlideAt: slideIndex)
    try document.write(to: outputURL)
    print("cloned node \(nodeID) onto slide \(slideIndex) as node \(newID)")

case "builds":
    guard arguments.count >= 4, let slideIndex = Int(arguments[3]) else { fail(usage) }
    let document = try KeynoteDocument(contentsOf: inputURL)
    for build in try document.slideBuilds(at: slideIndex) {
        print("build \(build.id): node=\(build.nodeID) \(build.kind) \(build.effect) duration=\(build.duration) delay=\(build.delay)")
    }

case "add-build":
    guard arguments.count >= 8, let slideIndex = Int(arguments[4]), let nodeID = UInt64(arguments[5]) else { fail(usage) }
    let outputURL = URL(fileURLWithPath: arguments[3])
    var document = try KeynoteDocument(contentsOf: inputURL)
    let duration = arguments.count >= 9 ? Double(arguments[8]) ?? 1.0 : 1.0
    let delivery = arguments.count >= 10 ? arguments[9] : nil
    let buildID = try document.addBuild(
        SlideBuild(nodeID: nodeID, kind: arguments[6], effect: arguments[7], duration: duration, delivery: delivery),
        toSlideAt: slideIndex
    )
    try document.write(to: outputURL)
    print("added build \(buildID) to node \(nodeID)")

case "reorder-builds":
    guard arguments.count >= 6, let slideIndex = Int(arguments[4]) else { fail(usage) }
    let outputURL = URL(fileURLWithPath: arguments[3])
    var document = try KeynoteDocument(contentsOf: inputURL)
    let order = arguments[5].split(separator: ",").compactMap { UInt64($0) }
    try document.reorderBuilds(onSlideAt: slideIndex, order: order)
    try document.write(to: outputURL)
    print("reordered builds: \(order)")

case "remove-build":
    guard arguments.count >= 6, let slideIndex = Int(arguments[4]), let buildID = UInt64(arguments[5]) else { fail(usage) }
    let outputURL = URL(fileURLWithPath: arguments[3])
    var document = try KeynoteDocument(contentsOf: inputURL)
    try document.removeBuild(buildID, fromSlideAt: slideIndex)
    try document.write(to: outputURL)
    print("removed build \(buildID)")

case "set-transition":
    guard arguments.count >= 6, let slideIndex = Int(arguments[4]) else { fail(usage) }
    let outputURL = URL(fileURLWithPath: arguments[3])
    var document = try KeynoteDocument(contentsOf: inputURL)
    let effect = arguments[5]
    if effect == "none" {
        try document.setSlideTransition(at: slideIndex, to: nil)
    } else {
        let duration = arguments.count >= 7 ? Double(arguments[6]) ?? 1.0 : 1.0
        try document.setSlideTransition(
            at: slideIndex,
            to: SlideTransition(effect: effect, duration: duration)
        )
    }
    try document.write(to: outputURL)
    print("set transition of slide \(slideIndex) to \(effect)")

case "set-cell":
    guard arguments.count >= 8, let nodeID = UInt64(arguments[4]),
          let row = Int(arguments[5]), let column = Int(arguments[6]) else { fail(usage) }
    let outputURL = URL(fileURLWithPath: arguments[3])
    var document = try KeynoteDocument(contentsOf: inputURL)
    let value = arguments[7]
    if let number = Double(value) {
        try document.setTableCellNumber(nodeID, row: row, column: column, to: number)
    } else {
        try document.setTableCellText(nodeID, row: row, column: column, to: value)
    }
    try document.write(to: outputURL)
    print("set cell [\(row),\(column)] of table \(nodeID)")

case "set-text", "set-frame", "set-media", "delete-node":
    guard arguments.count >= 5, let nodeID = UInt64(arguments[4]) else { fail(usage) }
    let outputURL = URL(fileURLWithPath: arguments[3])
    var document = try KeynoteDocument(contentsOf: inputURL)
    switch command {
    case "set-text":
        guard arguments.count >= 6 else { fail(usage) }
        try document.setNodeText(nodeID, to: arguments[5])
    case "set-frame":
        guard arguments.count >= 9,
              let x = Double(arguments[5]), let y = Double(arguments[6]),
              let w = Double(arguments[7]), let h = Double(arguments[8]) else { fail(usage) }
        try document.setNodeFrame(nodeID, to: Frame(x: x, y: y, width: w, height: h))
    case "set-media":
        guard arguments.count >= 6 else { fail(usage) }
        try document.setNodeMedia(nodeID, to: try Data(contentsOf: URL(fileURLWithPath: arguments[5])))
    default:
        try document.deleteDrawable(nodeID)
    }
    try document.write(to: outputURL)
    print("\(command) applied to node \(nodeID)")

case "apply-tree":
    guard arguments.count >= 5 else { fail(usage) }
    let outputURL = URL(fileURLWithPath: arguments[3])
    var document = try KeynoteDocument(contentsOf: inputURL)
    let treeData = try Data(contentsOf: URL(fileURLWithPath: arguments[4]))
    let trees = try JSONDecoder().decode([SceneTree].self, from: treeData)
    for tree in trees {
        try document.apply(tree)
    }
    try document.write(to: outputURL)
    print("applied \(trees.count) slide tree(s)")

case "replace-image":
    guard arguments.count >= 6 else { fail(usage) }
    let outputURL = URL(fileURLWithPath: arguments[3])
    var document = try KeynoteDocument(contentsOf: inputURL)
    let newData = try Data(contentsOf: URL(fileURLWithPath: arguments[5]))
    let replaced = try document.replaceImage(named: arguments[4], with: newData)
    try document.write(to: outputURL)
    print("replaced \(replaced.joined(separator: ", "))")

case "set-title":
    guard arguments.count >= 6, let index = Int(arguments[4]) else { fail(usage) }
    let outputURL = URL(fileURLWithPath: arguments[3])
    var document = try KeynoteDocument(contentsOf: inputURL)
    try document.setSlideText(at: index, .title, to: arguments[5])
    try document.write(to: outputURL)
    print("set title of slide \(index)")

case "build":
    // Outline format: a line starting with "# " begins a new slide (its
    // title); subsequent non-blank lines are that slide's body.
    guard arguments.count >= 4 else { fail(usage) }
    let outputURL = URL(fileURLWithPath: arguments[3])
    let outline = try String(contentsOf: inputURL, encoding: .utf8)
    var slides: [Slide] = []
    var currentBody: [String] = []
    func flushBody() {
        if !slides.isEmpty, !currentBody.isEmpty {
            slides[slides.count - 1].body = currentBody.joined(separator: "\n")
        }
        currentBody = []
    }
    for line in outline.split(separator: "\n", omittingEmptySubsequences: false) {
        if line.hasPrefix("# ") {
            flushBody()
            slides.append(Slide(title: String(line.dropFirst(2))))
        } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
            currentBody.append(String(line))
        }
    }
    flushBody()
    let writer = try KeynoteWriter()
    try writer.write(Presentation(slides: slides), to: outputURL)
    print("built \(slides.count)-slide deck")

case "build-md":
    guard arguments.count >= 4 else { fail(usage) }
    let outputURL = URL(fileURLWithPath: arguments[3])
    let templateURL = arguments.count >= 5 ? URL(fileURLWithPath: arguments[4]) : nil
    let presentation = try Presentation(markdownFileURL: inputURL)
    let imageCount = presentation.slides.reduce(0) { $0 + $1.imagePaths.count }
    let writer = try KeynoteWriter(templateURL: templateURL)
    try writer.write(
        presentation,
        to: outputURL,
        imageBaseURL: inputURL.deletingLastPathComponent()
    )
    var message = "built \(presentation.slides.count)-slide deck from markdown"
    if imageCount > 0 {
        message += " (\(imageCount) image reference(s))"
    }
    print(message)

case "build-json":
    guard arguments.count >= 4 else { fail(usage) }
    let outputURL = URL(fileURLWithPath: arguments[3])
    do {
        try DeckSpecLoader.write(specURL: inputURL, to: outputURL)
        print("built deck from JSON: \(outputURL.path)")
    } catch let error as DeckSpecError {
        fail("\(error)")
    }

default:
    fail(usage)
}
