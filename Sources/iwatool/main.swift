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
  iwatool build <outline.txt> <out.key>          build a deck from a simple outline
  iwatool set-title <in.key> <out.key> <index> <text>   set a slide's title
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

let arguments = CommandLine.arguments
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
            print("=== id \(id) type \(info.type) refs \(info.objectReferences)\(fieldInfoNote) ===")
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

case "list-media":
    let document = try KeynoteDocument(contentsOf: inputURL)
    for name in document.mediaFileNames {
        print(name)
    }

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

default:
    fail(usage)
}
