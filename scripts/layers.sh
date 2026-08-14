#!/bin/sh
# The layer rule from coding-standards.md §1, made mechanical. A file's layer
# is its directory; these greps are the enforcement. Run in review; move into
# CI the day CI exists.
set -u
cd "$(dirname "$0")/.." || exit 1
fail=0

check() {
    hits=$(grep -rl "$2" Sources --include='*.swift' | grep -v "^Sources/$3/" || true)
    if [ -n "$hits" ]; then
        echo "FAIL  $1"
        echo "$hits" | sed 's/^/        /'
        fail=1
    else
        echo "ok    $1"
    fi
}

check "Vision only in Tools"      'import Vision'      'Tools'
check "PDFKit only in Tools"      'import PDFKit'      'Tools'
check "SwiftUI only in UI"        'import SwiftUI'     'UI\|PigeonEye'
check "no egress outside Gate"    'URLSession\|http'   'Gate'

# §1:42 — "No other root-level file gets that grace." A file's layer is its
# directory, so a file at the root has no layer and no import rule. The root is
# therefore an allowlist: entry-point docs, the manifest, and nothing else.
# Everything with a layer lives in Sources/; prototypes that have not earned one
# live in spikes/. Build artifacts are gitignored and so never enumerated here.
strays=$(git ls-files --cached --others --exclude-standard | grep -v / | grep -vxF \
    -e .gitignore -e AGENTS.md -e CLAUDE.md -e Package.swift -e README.md \
    -e ai-workflow.md -e coding-standards.md -e issues.md -e ocr)
if [ -n "$strays" ]; then
    echo "FAIL  root holds only entry-point docs"
    echo "$strays" | sed 's/^/        /'
    fail=1
else
    echo "ok    root holds only entry-point docs"
fi

exit $fail
