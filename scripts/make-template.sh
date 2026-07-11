#!/bin/bash
# Creates a tagged multi-layout template deck from a Keynote theme.
#
# Makes a new document from the named theme and adds one slide per master
# (slide layout) the theme defines, tagged in its presenter notes with
# "@layout: <master name>" so TemplateLibrary/KeynoteWriter can find it.
# The theme — masters, styles, backgrounds — travels inside the file.
#
# Placeholders get sample text typed into them so their text storages carry
# the theme's real styles; generated content inherits them.
#
# Usage:
#   scripts/make-template.sh "Basic Black" /path/to/template.key
#
# Theme names are Keynote's own ("White", "Basic Black", "Gradient", …).
set -euo pipefail

THEME="${1:?usage: make-template.sh <theme name> <output.key>}"
OUTPUT="${2:?usage: make-template.sh <theme name> <output.key>}"

osascript - "$THEME" "$OUTPUT" <<'EOF'
on run {themeName, outputPath}
    tell application id "com.apple.Keynote"
        set theDoc to make new document with properties {document theme:theme themeName}
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
