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

exit $fail
