#!/bin/bash
# Creates a tagged multi-layout template deck from a Keynote theme.
#
# The source can be either:
#   - the name of a theme installed in Keynote ("Basic Black", "Gradient"), or
#   - a path to a custom theme (.kth) or document (.key) file.
#
# Makes a document from the source and adds one slide per master (slide
# layout) it defines, tagged in its presenter notes with
# "@layout: <master name>" so TemplateLibrary/KeynoteWriter can find it.
# The theme — masters, styles, backgrounds — travels inside the file.
#
# Placeholders get sample text typed into them so their text storages carry
# the theme's real styles; generated content inherits them.
#
# Usage:
#   scripts/make-template.sh "Basic Black"        out.key   # installed theme
#   scripts/make-template.sh MyTheme.kth          out.key   # custom .kth
#   scripts/make-template.sh Existing.key         out.key   # any document
set -euo pipefail

SOURCE="${1:?usage: make-template.sh <theme name | .kth | .key> <output.key>}"
OUTPUT="${2:?usage: make-template.sh <theme name | .kth | .key> <output.key>}"

# A .kth can't be opened directly by AppleScript (it triggers the theme
# chooser and blocks), but it IS a valid single-slide document — copying it
# to a .key lets Keynote open it normally. Resolve the source to either a
# theme name or an openable .key path.
OPEN_PATH=""
CLEANUP=""
case "$SOURCE" in
    *.kth)
        # Place the temp copy next to the output (a location the caller can
        # already write to); Keynote's sandbox rejects some temp dirs
        # ("Operation not permitted").
        OUTPUT_DIR="$(cd "$(dirname "$OUTPUT")" && pwd)"
        OPEN_PATH="$OUTPUT_DIR/make-template-source-$$.key"
        # Use `cat` (not `cp`) and clear extended attributes: a .kth from
        # /Applications carries a com.apple.provenance pointing at a
        # protected location, and Keynote's sandbox refuses to open a copy
        # that inherits it ("Operation not permitted").
        cat "$SOURCE" > "$OPEN_PATH"
        xattr -c "$OPEN_PATH" 2>/dev/null || true
        CLEANUP="$OPEN_PATH"
        ;;
    *.key)
        OPEN_PATH="$(cd "$(dirname "$SOURCE")" && pwd)/$(basename "$SOURCE")"
        ;;
esac
trap '[ -n "$CLEANUP" ] && rm -f "$CLEANUP"' EXIT

# Opening via the shell's `open -a` (LaunchServices) avoids the sandbox
# rejection that AppleScript's `open` triggers for arbitrary paths.
if [ -n "$OPEN_PATH" ]; then
    open -a "Keynote" "$OPEN_PATH" 2>/dev/null || open -a "Keynote Creator Studio" "$OPEN_PATH"
    sleep 5
fi

osascript - "$SOURCE" "$OUTPUT" "$OPEN_PATH" <<'EOF'
on run {source, outputPath, openPath}
    tell application id "com.apple.Keynote"
        if openPath is "" then
            set theDoc to make new document with properties {document theme:theme source}
        else
            set theDoc to front document
        end if

        set masterNames to name of every master slide of theDoc
        set firstDone to false
        repeat with masterName in masterNames
            set masterName to masterName as string
            try
                if firstDone then
                    set s to make new slide at end of theDoc with properties {base slide:master slide masterName of theDoc}
                else
                    tell theDoc to set base slide of slide 1 to master slide masterName
                    set s to slide 1 of theDoc
                    set firstDone to true
                end if
                -- Type into the placeholders so their text storages carry
                -- the theme's real styles (an untouched placeholder has no
                -- style tables, and programmatic text would fall back to
                -- defaults).
                tell s
                    try
                        set object text of default title item to "Title"
                    end try
                    try
                        set object text of default body item to "Body"
                    end try
                end tell
                set presenter notes of s to "@layout: " & masterName
            on error errMsg
                log "skipping master '" & masterName & "': " & errMsg
            end try
        end repeat
        save theDoc in POSIX file outputPath
        close theDoc saving no
    end tell
    return "created " & outputPath
end run
EOF
