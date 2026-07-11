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
  iwatool set-title <in.key> <out.key> <index> <text>   set a slide's title
  iwatool describe-template <file.key>           JSON: each slide's layout tag, master, and
                                                 fillable placeholders (role/kind/prompt/frame)
  iwatool tree <file.key> [slide-index]          JSON scene tree: every node (placeholder,
                                                 image, shape, group...) with id/role/text/
                                                 frame/media, z-ordered
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

let arguments = CommandLine.arguments

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
    let buildID = try document.addBuild(
        SlideBuild(nodeID: nodeID, kind: arguments[6], effect: arguments[7], duration: duration),
        toSlideAt: slideIndex
    )
    try document.write(to: outputURL)
    print("added build \(buildID) to node \(nodeID)")

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

default:
    fail(usage)
}
