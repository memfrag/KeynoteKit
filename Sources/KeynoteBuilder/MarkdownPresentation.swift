import Foundation

/// Parses a Marp/Deckset-style markdown presentation into a `Presentation`.
///
/// Format:
/// - A line containing only `---` (three or more hyphens) separates slides.
/// - The first `#` heading in a slide becomes its title (any heading level).
/// - Bullet lines (`-`, `*`, `+`) and paragraphs become the body, one
///   paragraph per line; blank lines separate paragraphs.
/// - `![alt](path)` images are collected into `imagePaths` (placement lands
///   with M4; parsed now so the format is stable).
/// - A `Notes:` line, or a `<!-- notes: … -->` comment, starts presenter
///   notes; following lines until the next slide are appended to the notes.
///
/// Leading YAML front matter (a `---` fenced block at the very top) is
/// skipped, matching common markdown-slide tools.
public enum MarkdownPresentation {

    public static func parse(_ markdown: String) -> Presentation {
        var source = markdown

        // Skip a leading YAML front-matter block (--- … ---) at the top.
        if source.hasPrefix("---\n") || source.hasPrefix("---\r\n") {
            let lines = source.components(separatedBy: "\n")
            if let closing = lines.dropFirst().firstIndex(where: { isSlideSeparator($0) }) {
                source = lines[(closing + 1)...].joined(separator: "\n")
            }
        }

        var slides: [Slide] = []
        for block in splitSlides(source) {
            if let slide = parseSlide(block) {
                slides.append(slide)
            }
        }
        return Presentation(slides: slides)
    }

    // MARK: Slide splitting

    private static func isSlideSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count >= 3 && trimmed.allSatisfy { $0 == "-" }
    }

    private static func splitSlides(_ source: String) -> [String] {
        var blocks: [String] = []
        var current: [String] = []
        for line in source.components(separatedBy: "\n") {
            if isSlideSeparator(line) {
                blocks.append(current.joined(separator: "\n"))
                current = []
            } else {
                current.append(line)
            }
        }
        blocks.append(current.joined(separator: "\n"))
        return blocks.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    // MARK: Single-slide parsing

    private static let notesPrefix = "notes:"
    private static let imagePattern = try! NSRegularExpression(pattern: #"!\[[^\]]*\]\(([^)]+)\)"#)

    private static func parseSlide(_ block: String) -> Slide? {
        var title: String?
        var bodyParagraphs: [String] = []
        var noteLines: [String] = []
        var collectedImages: [String] = []
        var layout: String?
        var inNotes = false

        for rawLine in block.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            // Layout directive: `<!-- layout: quote -->` or `layout: quote`.
            if let name = layoutDirective(line) {
                layout = name
                continue
            }

            // Notes section: `Notes:` or `<!-- notes: … -->`.
            if let noteBody = notesDirective(line) {
                inNotes = true
                if !noteBody.isEmpty { noteLines.append(noteBody) }
                continue
            }
            if inNotes {
                noteLines.append(rawLine)
                continue
            }

            if line.isEmpty { continue }

            // Images (may share a line with other markup).
            collectedImages.append(contentsOf: imagePaths(in: line))
            let withoutImages = stripImages(from: line)
            if withoutImages.isEmpty { continue }

            if withoutImages.hasPrefix("#") {
                let heading = withoutImages.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                if title == nil {
                    title = heading
                } else {
                    bodyParagraphs.append(heading)
                }
                continue
            }

            bodyParagraphs.append(stripBullet(from: withoutImages))
        }

        let notes = noteLines.isEmpty
            ? nil
            : noteLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        if title == nil, bodyParagraphs.isEmpty, notes == nil, collectedImages.isEmpty, layout == nil {
            return nil
        }
        return Slide(
            title: title,
            body: bodyParagraphs.isEmpty ? nil : bodyParagraphs.joined(separator: "\n"),
            notes: notes,
            layout: layout,
            imagePaths: collectedImages
        )
    }

    private static func notesDirective(_ line: String) -> String? {
        let lower = line.lowercased()
        if lower.hasPrefix(notesPrefix) {
            return String(line.dropFirst(notesPrefix.count)).trimmingCharacters(in: .whitespaces)
        }
        if lower.hasPrefix("<!--"), lower.contains(notesPrefix) {
            var inner = line
            inner.removeFirst(4) // <!--
            if let range = inner.range(of: "-->") { inner.removeSubrange(range.lowerBound..<inner.endIndex) }
            let trimmed = inner.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix(notesPrefix) {
                return String(trimmed.dropFirst(notesPrefix.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private static let layoutPrefix = "layout:"

    private static func layoutDirective(_ line: String) -> String? {
        let lower = line.lowercased()
        if lower.hasPrefix(layoutPrefix) {
            return String(line.dropFirst(layoutPrefix.count)).trimmingCharacters(in: .whitespaces)
        }
        if lower.hasPrefix("<!--"), lower.contains(layoutPrefix) {
            var inner = line
            inner.removeFirst(4)
            if let range = inner.range(of: "-->") { inner.removeSubrange(range.lowerBound..<inner.endIndex) }
            let trimmed = inner.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix(layoutPrefix) {
                return String(trimmed.dropFirst(layoutPrefix.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private static func stripBullet(from line: String) -> String {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        return line
    }

    private static func imagePaths(in line: String) -> [String] {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return imagePattern.matches(in: line, range: range).compactMap { match in
            guard let captureRange = Range(match.range(at: 1), in: line) else { return nil }
            return String(line[captureRange])
        }
    }

    private static func stripImages(from line: String) -> String {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        let stripped = imagePattern.stringByReplacingMatches(in: line, range: range, withTemplate: "")
        return stripped.trimmingCharacters(in: .whitespaces)
    }
}

extension Presentation {
    /// Parses markdown into a presentation. See `MarkdownPresentation`.
    public init(markdown: String) {
        self = MarkdownPresentation.parse(markdown)
    }

    public init(markdownFileURL url: URL) throws {
        self = MarkdownPresentation.parse(try String(contentsOf: url, encoding: .utf8))
    }
}
