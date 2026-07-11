# The Markdown Presentation Format

Author a whole deck as one markdown file, in the style of Marp and Deckset.

## Overview

``MarkdownPresentation`` parses markdown into a ``Presentation``; combine
it with a template and ``KeynoteWriter`` to go from text to `.key`:

```swift
let deck = try Presentation(markdownFileURL: URL(filePath: "talk.md"))
let writer = try KeynoteWriter(templateURL: URL(filePath: "MyTemplate.key"))
try writer.write(deck, to: URL(filePath: "talk.key"),
                 imageBaseURL: URL(filePath: "."))
```

Or from the command line:

```bash
iwatool build-md talk.md talk.key MyTemplate.key
```

## The format

**Slides.** A line of three or more hyphens (`---`) starts a new slide.
Blocks with no content are skipped.

**Front matter.** An optional YAML block fenced by `---` at the very top
(title, author, anything) is ignored, so metadata for other tools is safe
to keep.

**Title.** The first heading in a slide — any level — becomes its title.
Later headings in the same slide join the body.

**Body.** Bullet lines (`-`, `*`, `+`) and plain paragraphs become the
body, one line each. Bullet markers are stripped; the layout's list style
supplies them. Blank lines are ignored.

**Presenter notes.** A line starting with `Notes:` sends it and everything
after (until the next slide) to the presenter notes. The HTML-comment form
`<!-- notes: … -->` does the same while staying invisible in other markdown
renderers.

**Layout.** `<!-- layout: name -->` (or a bare `layout: name` line) picks
the template slide to clone, matched case-insensitively against the
template's tags or master names. Without it, the writer's `defaultLayout`
(`"bullets"`) applies.

**Images.** `![alt](path)` places the image into the slide's layout,
replacing the layout's picture. Paths resolve relative to the markdown
file. Choose a layout that shows a picture; slides whose layout has no
image node leave references unplaced.

## A complete example

```markdown
---
title: Quarterly Review
---

# Q3 Review
<!-- layout: title -->

Results and outlook

Notes: Welcome everyone. Keep the intro under a minute.

---

# Highlights
<!-- layout: bullets -->

- Revenue up 40%
- Churn at an all-time low
- Two new markets opened

---

# Our best quarter yet.
<!-- layout: statement -->

---

# The new factory
<!-- layout: photo -->

![factory floor](images/factory.jpg)

<!-- notes: Photo taken during the September visit. -->
```

Four slides: a title slide, a bulleted content slide, a big centered
statement (single text block → the layout's prominent placeholder), and a
full-bleed photo with private notes.
