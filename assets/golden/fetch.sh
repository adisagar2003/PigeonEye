#!/bin/sh
# Download and normalise the public golden sets. Idempotent: skips what exists.
# See README.md for what each set scores. Stdlib python3 only, no pip install.
#
#   ./assets/golden/fetch.sh          # everything except NIST (200 MB+)
#   ./assets/golden/fetch.sh nist     # NIST too
set -eu
cd "$(dirname "$0")"

get() {  # get <url> <dest>
    [ -s "$2" ] && { echo "have  $2"; return 0; }
    echo "fetch $2"
    mkdir -p "$(dirname "$2")"
    curl -fsSL --retry 3 -o "$2.part" "$1" && mv "$2.part" "$2"
}

# --- FUNSD: 199 noisy scanned forms, word-level text + bboxes + q/a links ----
if [ ! -d funsd/dataset ]; then
    get https://guillaumejaume.github.io/FUNSD/dataset.zip funsd/dataset.zip
    unzip -q -o funsd/dataset.zip -d funsd
    rm -rf funsd/__MACOSX funsd/dataset.zip
fi

# --- Kleister Charity: long docs, typed fields, decoy keys ------------------
KL=https://raw.githubusercontent.com/applicaai/kleister-charity/master
get $KL/dev-0/expected.tsv kleister-charity/dev-0.expected.tsv
get $KL/README.md          kleister-charity/README.md
if [ ! -s kleister-charity/kleister-charity-dev-200.jsonl ]; then
    get $KL/dev-0/in.tsv.xz kleister-charity/dev-0.in.tsv.xz
    xz -dkf kleister-charity/dev-0.in.tsv.xz
    python3 - <<'PY'
import csv, json, sys
csv.field_size_limit(sys.maxsize)
COLS = ["filename", "keys", "text_djvu", "text_tesseract", "text_textract", "text_best"]

def parse(line):
    out = {}
    for tok in line.split():
        if "=" in tok:
            k, v = tok.split("=", 1)
            out.setdefault(k, []).append(v.replace("_", " "))
    return {k: (v[0] if len(v) == 1 else v) for k, v in out.items()}

exp = [parse(l) for l in open("kleister-charity/dev-0.expected.tsv", encoding="utf-8")]
rows = list(csv.reader(open("kleister-charity/dev-0.in.tsv", encoding="utf-8"),
                       delimiter="\t", quoting=csv.QUOTE_NONE))
assert len(exp) == len(rows), (len(exp), len(rows))
with open("kleister-charity/kleister-charity-dev-200.jsonl", "w", encoding="utf-8") as f:
    for d, e in list(zip((dict(zip(COLS, r)) for r in rows), exp))[:200]:
        keys = d["keys"].split()
        f.write(json.dumps({
            "id": d["filename"].replace(".pdf", ""),
            "keys_requested": keys,
            "decoy_keys": [k for k in keys if k not in e],  # a value here = hallucination
            "expected": e,
            "text_clean": d["text_best"],      # born-digital extraction
            "text_ocr": d["text_tesseract"],   # tesseract on the same pages
        }, ensure_ascii=False) + "\n")
print("kleister: wrote 200 docs")
PY
    rm -f kleister-charity/dev-0.in.tsv kleister-charity/dev-0.in.tsv.xz
fi

# --- GovReport: 200 GAO/CRS reports + expert summaries ----------------------
if [ ! -s govreport/govreport-validation-200.jsonl ]; then
    python3 - <<'PY'
import json, urllib.request
B = ("https://datasets-server.huggingface.co/rows?dataset=ccdv%2Fgovreport-summarization"
     "&config=document&split=validation")
rows = []
for off in (0, 100):
    with urllib.request.urlopen(f"{B}&offset={off}&length=100", timeout=60) as r:
        rows += [x["row"] for x in json.load(r)["rows"]]
import os; os.makedirs("govreport", exist_ok=True)
with open("govreport/govreport-validation-200.jsonl", "w", encoding="utf-8") as f:
    for i, r in enumerate(rows):
        f.write(json.dumps({"id": f"govreport-val-{i:03d}",
                            "report": r["report"], "summary": r["summary"]}) + "\n")
print(f"govreport: wrote {len(rows)} reports")
PY
fi

# --- CUAD: 13k lawyer-labelled obligation spans -----------------------------
get https://zenodo.org/records/4595826/files/CUAD_v1.zip cuad/CUAD_v1.zip

# --- NIST SFRS2: IRS forms incl. Schedule F. 200 MB+, opt in ---------------
case "${1:-}" in
    nist) get https://s3.amazonaws.com/nist-srd/SD6/sd06.zip nist-sfrs/sd06.zip ;;
    *)    echo "skip  nist-sfrs (200 MB+) - run '$0 nist' to include it" ;;
esac

echo "done. see $(dirname "$0")/README.md"
