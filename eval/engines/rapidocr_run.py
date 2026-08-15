"""RapidOCR wrapper — portable OCR (ONNX, no PyTorch, runs on macOS/Linux/Windows).

Two modes, matching what the `ocr` CLI (`Sources/Tools/OCR.swift`) gives us so the
tool layer can swap engines without the caller knowing:

    python eval/engines/rapidocr_run.py page.jpg           # plain text, reading order
    python eval/engines/rapidocr_run.py page.jpg --json    # text + confidence + bbox

Plain-text mode is what eval/ocr_bench.py scores. JSON mode is what the
confidence gate needs, and it's the reason RapidOCR is a real candidate rather
than just a text extractor: it reports per-line confidence like Vision does.
"""

import json
import sys
from pathlib import Path

from rapidocr_onnxruntime import RapidOCR

# Two boxes belong to the same visual line if their vertical centres sit within
# this fraction of the page height. Purely for reconstructing reading order.
LINE_TOL = 0.012


def read(path: str):
    engine = RapidOCR()
    result, _elapse = engine(path)
    if not result:
        return []

    items = []
    for box, text, conf in result:
        ys = [p[1] for p in box]
        xs = [p[0] for p in box]
        items.append({
            "text": text,
            "confidence": float(conf),
            "x0": min(xs), "y0": min(ys), "x1": max(xs), "y1": max(ys),
            "cy": sum(ys) / len(ys),
        })
    return items


def to_lines(items, page_height: float):
    """Group boxes into visual lines, top-to-bottom then left-to-right."""
    tol = max(page_height * LINE_TOL, 1.0)
    lines, current = [], []
    for it in sorted(items, key=lambda i: i["cy"]):
        if current and abs(it["cy"] - current[-1]["cy"]) > tol:
            lines.append(sorted(current, key=lambda i: i["x0"]))
            current = []
        current.append(it)
    if current:
        lines.append(sorted(current, key=lambda i: i["x0"]))
    return lines


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    as_json = "--json" in sys.argv
    if len(args) != 1:
        print("usage: rapidocr_run.py <image> [--json]", file=sys.stderr)
        return 2

    path = args[0]
    if not Path(path).exists():
        print(f"no such image: {path}", file=sys.stderr)
        return 2

    items = read(path)
    if not items:
        print("rapidocr returned nothing", file=sys.stderr)
        return 1

    page_height = max(i["y1"] for i in items) or 1.0
    lines = to_lines(items, page_height)

    if as_json:
        out = [{k: v for k, v in i.items() if k != "cy"} for line in lines for i in line]
        print(json.dumps(out))
    else:
        for line in lines:
            print(" ".join(i["text"] for i in line))
    return 0


if __name__ == "__main__":
    sys.exit(main())
