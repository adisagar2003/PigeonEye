"""Benchmark any OCR engine against born-digital ground truth.

The trick that makes this free: the government PDFs in assets/ are born-digital,
so `pdftotext` on the ORIGINAL pdf is near-perfect ground truth, while
assets/scans/*.jpg are the same pages deliberately degraded by degrade.sh. So we
have a real OCR benchmark with no hand-labelling.

    # incumbent
    .venv/bin/python eval/ocr_bench.py --label apple-vision

    # challenger, once mere.run is built (it prints plain text to stdout too)
    .venv/bin/python eval/ocr_bench.py --label mere \\
        --engine 'swift run mere.run vision ocr {img}'

    # compare two saved runs
    .venv/bin/python eval/ocr_bench.py --compare out-apple.json out-mere.json

Three metrics, because they fail differently:
  CER  character error rate      - raw transcription fidelity
  WER  word error rate           - readable-word fidelity, order-sensitive
  BER  bag-of-words error rate   - order-INSENSITIVE, so a two-column form read
                                   in a different order is not punished as if
                                   the characters were wrong
A big WER with a small BER means "right words, wrong order" - a reading-order
problem, not an accuracy problem. That distinction matters for forms.
"""

import argparse
import difflib
import json
import re
import subprocess
import sys
import unicodedata
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).parent.parent
SCANS = ROOT / "assets" / "scans"
PDF_DIRS = [ROOT / "assets" / "epa-labels", ROOT / "assets" / "gov-forms"]

# Typographic characters pdftotext preserves but OCR flattens. Penalising these
# would measure font handling, not transcription accuracy.
FOLD = {"–": "-", "—": "-", "‘": "'", "’": "'",
        "“": '"', "”": '"', " ": " ", "ﬁ": "fi", "ﬂ": "fl"}


def norm(s: str) -> str:
    s = unicodedata.normalize("NFKC", s)
    for k, v in FOLD.items():
        s = s.replace(k, v)
    return re.sub(r"\s+", " ", s).strip()


def cer(truth: str, hyp: str) -> float:
    """Character error rate via difflib opcodes (fast; upper bound on edit distance)."""
    if not truth:
        return 0.0 if not hyp else 1.0
    sm = difflib.SequenceMatcher(None, truth, hyp, autojunk=False)
    edits = sum(max(i2 - i1, j2 - j1)
                for tag, i1, i2, j1, j2 in sm.get_opcodes() if tag != "equal")
    return edits / len(truth)


def wer(truth: str, hyp: str) -> float:
    """Word error rate, exact word-level Levenshtein."""
    a, b = truth.split(), hyp.split()
    if not a:
        return 0.0 if not b else 1.0
    prev = list(range(len(b) + 1))
    for i, wa in enumerate(a, 1):
        cur = [i]
        for j, wb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (wa != wb)))
        prev = cur
    return prev[-1] / len(a)


def ber(truth: str, hyp: str) -> float:
    """Bag-of-words error rate - order-insensitive, so column order is free."""
    a, b = Counter(truth.split()), Counter(hyp.split())
    total = sum(a.values())
    if not total:
        return 0.0 if not b else 1.0
    return sum(((a - b) + (b - a)).values()) / total


def find_pdf(base: str) -> Path | None:
    for d in PDF_DIRS:
        p = d / f"{base}.pdf"
        if p.exists():
            return p
    return None


def pairs():
    """(jpg, pdf, page) for every scan we can find a source PDF for."""
    for jpg in sorted(SCANS.glob("*.jpg")):
        m = re.match(r"^(.*)-(\d+)$", jpg.stem)
        if not m:
            continue
        pdf = find_pdf(m.group(1))
        if pdf:
            yield jpg, pdf, int(m.group(2))


def truth_for(pdf: Path, page: int) -> str:
    r = subprocess.run(["pdftotext", "-f", str(page), "-l", str(page), str(pdf), "-"],
                       capture_output=True, text=True)
    return norm(r.stdout)


def run_engine(cmd_tpl: str, jpg: Path) -> str:
    cmd = cmd_tpl.format(img=str(jpg))
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True, cwd=ROOT)
    if not r.stdout.strip():
        print(f"    !! no output: {r.stderr.strip()[:160]}", file=sys.stderr)
    return norm(r.stdout)


def bench(label: str, engine: str, limit: int | None) -> dict:
    rows = []
    todo = list(pairs())[:limit]
    if not todo:
        sys.exit("no scan/pdf pairs found - run assets/degrade.sh first")

    print(f"\n{'document':44} {'chars':>6} {'CER':>7} {'WER':>7} {'BER':>7}")
    print("-" * 76)
    for jpg, pdf, page in todo:
        t = truth_for(pdf, page)
        if len(t) < 200:          # cover pages / mostly-image pages aren't a fair test
            print(f"{jpg.stem:44} {len(t):>6}  (skipped: truth too short)")
            continue
        h = run_engine(engine, jpg)
        row = {"scan": jpg.name, "chars": len(t),
               "cer": cer(t, h), "wer": wer(t, h), "ber": ber(t, h)}
        rows.append(row)
        print(f"{jpg.stem:44} {row['chars']:>6} "
              f"{row['cer']:>7.3f} {row['wer']:>7.3f} {row['ber']:>7.3f}")

    if not rows:
        sys.exit("every page was skipped")

    # Weight by ground-truth length: a 2000-char page should count more than a 300-char one.
    tot = sum(r["chars"] for r in rows)
    agg = {m: sum(r[m] * r["chars"] for r in rows) / tot for m in ("cer", "wer", "ber")}
    print("-" * 76)
    print(f"{label + ' (length-weighted)':44} {tot:>6} "
          f"{agg['cer']:>7.3f} {agg['wer']:>7.3f} {agg['ber']:>7.3f}")
    print(f"\n  pages={len(rows)}  CER {agg['cer']:.1%}  WER {agg['wer']:.1%}  BER {agg['ber']:.1%}")
    return {"label": label, "engine": engine, "aggregate": agg, "pages": rows}


def compare(a_path: str, b_path: str) -> None:
    a, b = (json.loads(Path(p).read_text()) for p in (a_path, b_path))
    print(f"\n{'metric':8} {a['label']:>16} {b['label']:>16}   {'winner':>16}")
    print("-" * 62)
    for m in ("cer", "wer", "ber"):
        av, bv = a["aggregate"][m], b["aggregate"][m]
        win = a["label"] if av < bv else b["label"] if bv < av else "tie"
        print(f"{m.upper():8} {av:>16.3f} {bv:>16.3f}   {win:>16}")

    by_a = {r["scan"]: r for r in a["pages"]}
    diffs = [(r["scan"], by_a[r["scan"]]["cer"], r["cer"])
             for r in b["pages"] if r["scan"] in by_a]
    diffs.sort(key=lambda d: d[2] - d[1])
    print(f"\nbiggest per-page CER swings ({b['label']} minus {a['label']}):")
    for scan, av, bv in diffs[:3] + diffs[-3:]:
        print(f"  {scan:44} {av:.3f} -> {bv:.3f}  ({bv - av:+.3f})")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--engine", default="./ocr {img}",
                    help="shell command; {img} is substituted. Must print text to stdout.")
    ap.add_argument("--label", default="engine")
    ap.add_argument("--limit", type=int, default=None)
    ap.add_argument("--out", help="write JSON results here")
    ap.add_argument("--compare", nargs=2, metavar=("A.json", "B.json"))
    a = ap.parse_args()

    if a.compare:
        compare(*a.compare)
        return 0

    res = bench(a.label, a.engine, a.limit)
    if a.out:
        Path(a.out).write_text(json.dumps(res, indent=2))
        print(f"  wrote {a.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
