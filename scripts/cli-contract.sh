#!/bin/sh
# The `./ocr --json` shape is a contract, not an implementation detail: eval/ and
# spikes/page_index.py parse it, and F1's acceptance criteria name it. It had no
# check, which is how a fresh checkout came to have no ./ocr at all.
#
# Run from anywhere:  sh scripts/cli-contract.sh
set -u
cd "$(dirname "$0")/.." || exit 1
FIXTURE=assets/scans/007969-00242-20170111-01.jpg

if [ ! -x ./ocr ]; then
    echo "FAIL  ./ocr is missing or not executable — a fresh clone cannot run eval/"
    exit 1
fi

./ocr --json "$FIXTURE" > /tmp/ocr-contract.$$ 2>/dev/null
status=$?
python3 - "$status" <<'PY'
import json, os, sys
status, path = int(sys.argv[1]), f"/tmp/ocr-contract.{os.getppid()}"
def die(msg):
    print(f"FAIL  {msg}")
    sys.exit(1)
if status != 0:
    die(f"./ocr exited {status}")
try:
    pages = json.load(open(path))
except Exception as e:
    die(f"stdout is not JSON ({e}) — build noise on stdout breaks every caller")
if not isinstance(pages, list) or not pages:
    die("expected a non-empty JSON array, one object per page")
page = pages[0]
for key in ("transcript", "lines", "tables", "lists", "data"):
    if key not in page:
        die(f"page object is missing `{key}` — spikes/page_index.py reads it")
if not page["lines"]:
    die("no lines came back from a fixture known to produce them")
line = page["lines"][0]
for key in ("text", "conf", "bbox", "title", "alts"):
    if key not in line:
        die(f"line object is missing `{key}`")
if len(line["bbox"]) != 4:
    die("bbox must be [x, y, width, height] — I12")
print(f"ok    ./ocr --json contract ({len(pages)} page, {len(page['lines'])} lines)")
PY
result=$?
rm -f "/tmp/ocr-contract.$$"
exit $result
