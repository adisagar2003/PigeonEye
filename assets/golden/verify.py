"""Assert the golden sets are present and shaped as README.md claims.

    python3 assets/golden/verify.py

Doubles as a loader example - each block is the minimum code to read that set.
Stdlib only. Exits non-zero on the first broken claim.
"""

import json
import zipfile
from pathlib import Path

D = Path(__file__).parent
ok = lambda m: print(f"  ok  {m}")


def funsd():
    ann = sorted((D / "funsd/dataset/testing_data/annotations").glob("*.json"))
    assert len(ann) == 50, f"expected 50 test forms, got {len(ann)}"
    assert len(list((D / "funsd/dataset/training_data/annotations").glob("*.json"))) == 149
    ents = [e for f in ann for e in json.loads(f.read_text())["form"]]
    linked = [e for e in ents if e["linking"]]
    blank = [e for e in ents if not e["text"].strip()]
    assert {e["label"] for e in ents} == {"question", "answer", "header", "other"}
    assert linked, "no question/answer links - label-resolution ground truth missing"
    ok(f"funsd: 149 train + 50 test forms; test split has {len(ents)} entities, "
       f"{len(linked)} linked, {len(blank)} blank (filter these before CER)")


def kleister():
    rows = [json.loads(l) for l in (D / "kleister-charity/kleister-charity-dev-200.jsonl").open()]
    assert len(rows) == 200, len(rows)
    decoys = sum(len(r["decoy_keys"]) for r in rows)
    assert decoys, "no decoy keys - the hallucination test is gone"
    for r in rows:  # a decoy must never appear in expected, or it isn't a decoy
        assert not (set(r["decoy_keys"]) & set(r["expected"])), r["id"]
        assert r["text_clean"] and r["text_ocr"], r["id"]
    differ = sum(r["text_clean"] != r["text_ocr"] for r in rows)
    ok(f"kleister: 200 docs, {decoys} decoy keys, {differ} with clean!=ocr text")


def govreport():
    rows = [json.loads(l) for l in (D / "govreport/govreport-validation-200.jsonl").open()]
    assert len(rows) == 200, len(rows)
    assert all(r["report"] and r["summary"] for r in rows)
    words = sum(len(r["report"].split()) for r in rows) // len(rows)
    ok(f"govreport: 200 reports, mean {words} words - chunking required for local models")


def cuad():
    with zipfile.ZipFile(D / "cuad/CUAD_v1.zip") as z:
        names = z.namelist()
        j = next(n for n in names if n.endswith("CUAD_v1.json"))
        data = json.loads(z.read(j))["data"]
    spans = sum(len(qa["answers"]) for d in data for p in d["paragraphs"] for qa in p["qas"])
    ok(f"cuad: {len(data)} contracts, {spans} labelled spans")


def nist():
    p = D / "nist-sfrs/sd06.zip"
    if not p.exists():
        print("  --  nist-sfrs: not fetched (optional, ./fetch.sh nist)")
        return
    with zipfile.ZipFile(p) as z:
        n = z.namelist()
    ok(f"nist-sfrs: {len(n)} members, {p.stat().st_size / 1e6:.0f} MB")


for fn in (funsd, kleister, govreport, cuad, nist):
    try:
        fn()
    except FileNotFoundError as e:
        raise SystemExit(f"  MISSING  {fn.__name__}: {e.filename} - run ./assets/golden/fetch.sh")
print("all golden sets verified")
