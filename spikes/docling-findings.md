# Docling — measured against the rate-table failure

Spike branch `spike/docling`, run off `origin/main` @ `192b59a`. Answers one
question: **should docling replace or supplement the OCR tier?**

The failure it was pointed at is the one the tracker already records — page 34
of the flagship EPA label, the woody-brush rate table: 186 numbers in the file,
1 survives OCR through the app's path. A lost application rate is the failure
this product exists to prevent.

Reproduce anything below with:

```sh
python3 spikes/numeric_recall.py --self-check
swift spikes/spike_pdftext.swift <pdf> <page> | python3 spikes/numeric_recall.py <pdf> <page>
.venv/bin/python spikes/docling_run.py <pdf-or-jpg> <page> --mode ocr | python3 spikes/numeric_recall.py <pdf> <page>
```

## The metric

**Numeric recall**, multiset and order-insensitive: what fraction of the numeric
tokens in the file survive. Multiset matters — `1.6` appears 77 times on page 34,
and a set-based metric would score "recovered it once" as 1.0 and hide the whole
failure. Ground truth is free, because every page in `assets/` is born-digital
and `pdftotext` reads it exactly. `spikes/numeric_recall.py` counts 186 tokens on
page 34, agreeing with the number already in the tracker.

## What it measured

All three engines on the **same** inputs. Vision and docling were given the
byte-identical 150 dpi JPEG, so that column is a fair fight.

| Page | PDFKit text layer | Apple Vision | Docling |
|---|---|---|---|
| EPA `000524-00529` p34 — woody brush rates | **186/186 · 100%** | 9/186 · 4.8% | **185/186 · 99.5%** |
| EPA `000524-00529` p32 | **111/111 · 100%** | 34/111 · 30.6% | not run |
| EPA `000524-00529` p22 | **26/26 · 100%** | 14/26 · 53.8% | not run |
| `007969-00186` p1 — degraded photocopy | **22/22 · 100%** | 21/22 · 95.5% | 20/22 · 90.9% |
| IRS Schedule F p1 — scan | **139/139 · 100%** | 120/139 · 86.3% | 130/139 · 93.5% |
| NRCS CPA-1200 p1 — scan | **8/8 · 100%** | 8/8 · 100% | **3/8 · 37.5%** |

Vision's 9/186 differs from the tracker's 1/186 because this rasterised with
`pdftoppm` rather than the app's PDFKit render — 167 lines read where the app's
path read 55. Different rasteriser, same verdict.

## Four things this settles

**1. Docling really does fix the rate table.** 4.8% → 99.5% on the identical
pixels, and only the page number was lost. It confirms the tracker's own
diagnosis — *"not the pixels; whole-page layout analysis is what drops them"*.
Docling detects the table first and OCRs each cell separately, so the column is
never swallowed. This is a genuine capability Vision does not have.

**2. So does the text layer, for free, and better.** 100% on every page above,
from one line of PDFKit that is already linked. All 161 pages in `assets/` carry
a text layer. What blocks it is a **decision** — "OCR every page, always" — not a
missing engine. Any docling adoption that is really about the rate tables is
buying with 1 GB of Python what one line of PDFKit already does better.

**3. Docling is not a drop-in OCR replacement — it loses pages Vision keeps.**
NRCS CPA-1200 goes **100% → 37.5%**. The wins are on dense multi-column tables;
ordinary scanned pages are mixed to worse. Swapping the tier wholesale would
trade one class of failure for another.

**4. Its default OCR engine is the one this repo already rejected.** Docling
pulled **RapidOCR** (`ch_ptocr_mobile_v2.0_cls_mobile.pth` — the Chinese
recogniser) on first OCR run. The tracker ruled RapidOCR out on measurement:
NSCER 47.6% vs Apple's 26.2%. That it still reaches 99.5% on page 34 is a
compliment to the *layout* model, not the recogniser — and it means the obvious
first upgrade is to point docling's OCR at a better backend.

## What it costs

| | |
|---|---|
| Install | `docling` 2.120.1, `.venv` **1.0 GB**; free disk 9.1 → 5.3 GB |
| First page ever | **229 s** — model download plus `torch.compile` warmup |
| Warm, PDF input | **15.2 s/page** |
| Warm, image input | **29–50 s/page** |
| Today, whole 45-page label, render **and** OCR | **23.3 s** |

At 15.2 s/page the flagship label takes ~11 minutes against 23.3 s today —
roughly **30×**, and the image path is worse. It is also a Python subprocess and
a torch dependency in a product whose README currently says zero third-party
dependencies.

## Two integration costs nobody has priced

- **Per-line confidence.** `architecture.md` §12's composite and the escalate
  gate are built on Vision's per-line `confidence` and `boundingRegion`. Docling
  reports confidence per *page*, not per line. Whatever docling returns has to
  be adapted to that contract or the honesty story loses its input.
- **`force_full_page_ocr` is a trap on PDFs.** Setting it and converting a PDF
  returned text **byte-identical** to the text-layer run — the text layer still
  won, after paying 21 extra seconds to load an OCR engine. The only way to
  prove OCR ran is to feed it an image. Any benchmark that skips this measures
  the text layer and calls it OCR.

## What docling uniquely gives

Table **cells**. Page 34 came back as a 52 × 3 dataframe — species, broadcast
rate, spot rate — where PDFKit returns `Hornbeam, American* 1.6-4 0.8-1.6` as one
string you would have to re-split. "What is the rate for this species?" is the
product's core question on a label, and that pairing is the answer. This holds in
the 15.2 s/page text mode too, so the structure is available without the OCR
penalty.

## Recommendation

1. **Re-open "OCR every page, always" for values.** It is the whole rate-table
   failure and it costs one line. Keep OCR for geometry, confidence, and pages
   with no text layer.
2. **Do not swap the OCR tier to docling.** NRCS 100% → 37.5% and 30× the wall
   clock.
3. **Keep docling as a narrow, opt-in tool** for the case nothing else covers: a
   page with no text layer *and* a dense table. If that case gets built, point
   its OCR at something other than RapidOCR first.
