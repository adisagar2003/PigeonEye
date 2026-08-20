# 01 — Cross-platform migration, and whether OCR is the core at all

**Date:** 2026-08-19 · **Branch:** `migration/cross-platform-core` · **Status:** discussion, nothing built

Started as "the tool layer is Apple-only and the users are on Windows/Linux."
Ended somewhere more useful: the Apple lock-in is concentrated in the tier the
product needs *least*, and the extraction model underneath it is the wrong shape.
Both findings came out of measurements already in `context/progress-tracker.md`.

---

## 1. Swift is not the blocker — four frameworks are

Swift compiles on Linux and Windows. What does not port:

| File | Apple API | LOC | Portable swap |
|---|---|---|---|
| `Sources/Tools/OCR.swift` | Vision | 133 | Tesseract — **measured**, see §2 |
| `Sources/Agent/LocalModel.swift` | FoundationModels | 141 | Ollama / llama.cpp |
| `Sources/Tools/Raster.swift` | PDFKit | 92 | pdfium / poppler |
| `Sources/Tools/Findings.swift` | DataDetection | 243 | `Regex` (works on Linux) |
| `Sources/Tools/Export.swift` | CoreGraphics / CoreText | 244 | any PDF writer |
| `Sources/UI/*` | SwiftUI | ~2500 | the `web/` Next.js app |

Already portable, pure Foundation: `Contracts` (607), `Gate` (424), the rest of
`Agent` (~550). **~1700 tested LOC that needs no work.**

Swapping FoundationModels for Ollama is an upgrade, not a regression — it kills
the fixed 4096-token window that `LocalModel.swift:14` calls the constraint
forcing map-reduce chunking on whole-document explanation.

## 2. Portable OCR is already measured — do not re-litigate

`progress-tracker.md:663`, same 18 pages, same ground truth:

| Engine | CER | WER | BER | NSCER |
|---|---|---|---|---|
| **apple-vision** | 26.9% | 28.3% | **20.1%** | 26.2% |
| tesseract | 27.8% | 32.7% | 31.6% | 27.5% |
| rapidocr | 54.5% | 85.3% | 97.1% | 47.6% |

Tesseract is within 1 point on CER, 11 points worse on BER, 50 MB, installs
anywhere. RapidOCR stays rejected (Chinese-only recogniser). **The portable-OCR
bill is ~11 BER points on prose** — and §4 argues that bill is almost never paid.

## 3. Tauri — yes for the shell, no for the core

Proposal on the table: Rust + Tauri desktop app.

Verdict: right shape for the shell, wrong place for the logic.

- Tauri's Rust layer should be **~200 LOC of `#[tauri::command]` sidecar
  wrappers**. Writing the domain logic in Rust means rewriting the ~1700 tested
  portable LOC for no gain Swift-on-Linux doesn't already give — except Windows.
- Frontend reuses `web/` (already Next.js, already ours).
- Sidecar language: **Python**, because every Apple API being replaced has a
  mature Python binding and a painful Rust one — decisively so for **AcroForm
  widget + rect reading** (`pypdf`/`pikepdf` vs hand-rolling `lopdf`). Form mode
  is what saves us from Vision's reading-order collapse, so that path must not
  get harder. `eval/` is already Python, so sidecar and benchmark share a venv.
- `Contracts.swift` becomes the sidecar's JSON schema. The seam exists:
  `scripts/cli-contract.sh` already treats `./ocr --json` as a contract.

If the core is ported, **the tests port with it** — `swift test` → pytest.
`Contracts` is where a rewrite plants bugs (I1–I13, the §12 confidence
composite), and it is the one file that must not be ported on faith.

## 4. The reframe: OCR is a fallback tier, not the trunk

`assets/degrade.sh:2`, our own words:

> Government PDFs are born-digital, so pdftotext reads them perfectly and never
> exercises the OCR path. Render them to lossy images first: **that IS the test input.**

Every OCR page benchmarked in §2 is **synthetic**. There are 12 real government
PDFs in `assets/`, all with text layers, all readable at ~0% error — and 18
JPEGs we generated ourselves at 100 dpi / q40 to force the OCR path. **The
corpus contains no real scan.** We manufactured the problem to have one.

Consistent with the conclusion already logged at `progress-tracker.md:487`:
*"Vision is weakest precisely where OCR is unnecessary."*

**Route by provenance instead of one uniform pipeline:**

| Arrives as | Tool | Cost |
|---|---|---|
| Born-digital PDF (agency download — the common case) | embedded text layer | ~free, ~0% error |
| Fillable form with values | AcroForm widgets (63 / 89 / 105 fields measured) | ~free, ground truth |
| `.docx` / `.xlsx` | direct parse | ~free |
| Photo, fax, image-only scan | raster + OCR | 27% CER |

The router is one line: pull the text layer, and if chars-per-page is under a
threshold it's a scan (how `ocrmypdf` decides). Raster + OCR becomes a rarely
hit leaf — which is why §2's 11-point regression stops being load-bearing, and
why cross-platform gets *easier*: text-layer and AcroForm reading are trivially
portable. **The Apple lock-in was concentrated in the tier we need least.**

## 5. The bigger miss: extraction is the wrong shape

`progress-tracker.md:288`, our own words again:

> …an answer to "when is this due", and no amount of scrolling makes it one.

`Findings.swift` finds **every** date. The user wants **the deadline**. Those
are different problems and one is not a stepping stone to the other — hence the
two defects already logged: *"Half the findings were the same fact said twice"*
(`:252`) and `9/11/2008 → 9/11/2098`, *"a plausible wrong answer, which is the
dangerous kind"* (`:411`).

Entity detection is not the product. **Schema-constrained extraction** is:

```
{ deadline, amount_due, form_required, who_to_contact, penalty_if_late }
```

Both tiers to run it already exist — local (Ollama-class) and `Gate` for cloud.

**Keep the spans.** A model answer is unsourced prose unless it cites the span
it came from, and unsourced is precisely the failure already named at `:225`:
*"a wrong answer wearing the highest-trust signal in §12."* So:

- **model** → what the answer is
- **text-layer / OCR span + bbox** → where it came from, clickable and highlighted

Grounded extraction. The hard half is built (bboxes, crops, the origin-flip
regression test at `:192`). Regex's remaining job is not finding facts, it is
**validating** them: the model says "due March 14 2025", a date parser confirms
that string exists in the text layer at a real position. Model proposes, span
verifies. `Findings.swift` shrinks from detector-as-product to validator.

---

## Decisions reached

| # | Decision | Basis |
|---|---|---|
| D1 | Swift is not the blocker; six files and the UI are | import audit, §1 |
| D2 | Tesseract is the portable OCR tier. Do not re-benchmark | already measured, §2 |
| D3 | Tauri for the shell; domain logic in a sidecar, not in Rust | §3 |
| D4 | Sidecar is Python — AcroForm support decides it | §3 |
| D5 | Text layer → AcroForm → OCR, in that order. OCR is a leaf | `degrade.sh:2`, §4 |
| D6 | Extraction becomes schema-constrained; spans become citation | §5 |
| D7 | Any port of `Contracts` carries its test suite | I1–I13 risk, §3 |

## Open — these block the first line of code

| # | Question | Why it decides the architecture |
|---|---|---|
| Q1 | **Windows desktops, or a Linux server with a browser client?** | Linux-only → keep Swift, swap 6 files, everything stays tested, ~days. Windows → Tauri + Python sidecar is right and it is ~a month. |
| Q2 | **What does a real user document look like on arrival?** | Agency PDF download → §4 holds and OCR is a leaf. Photographed paper mail → OCR is the trunk after all and §4 inverts. **We own no real scan to answer this.** This is the missing measurement. |

Nothing gets built until Q1 and Q2 have answers. First slice once they do:
document in → router picks a path → one page rendered in the shell.

---

## 6. The stack

**2026-08-20.** Q1 is answered: all three desktops, one codebase. Offline-first
is the product (`project-overview.md` §3), so every tier below runs locally and
the network is an exception the user authorises.

| Layer | Pick | Replaces |
|---|---|---|
| Shell | **Tauri** — Rust wrapper, ~200 LOC of `#[tauri::command]` sidecar shims, no domain logic | — (D3) |
| UI | **Next.js** — the existing `web/` | `Sources/UI/*` (~2500 LOC, SwiftUI) |
| Core | **Python sidecar**, one process, `eval/`'s venv | — (D4) |
| Parse | **Docling** (MIT) — PDF/DOCX/XLSX/images, text layer → layout → reading order → table structure → OCR, one call | `Tools/Raster.swift` (PDFKit), `Tools/OCR.swift` (Vision), and D5's router |
| OCR fallback | **Tesseract**, behind Docling's flag | (D2 survives, demoted to a leaf) |
| Local model | **Ollama** + a Qwen3/Llama-class model, schema-constrained JSON out | `Agent/LocalModel.swift` (FoundationModels, and its 4096-token window) |
| Extraction | schema-constrained model output, spans as citation | `Tools/Findings.swift` (DataDetection) shrinks to a validator (D6) |
| Export | reportlab / fpdf | `Tools/Export.swift` (CoreGraphics/CoreText) |
| Cloud, consented | the existing `Gate` — one file, one socket | ported as-is |
| Packaging | Tauri bundles the sidecar; Ollama is a prerequisite install | — |

**Kept from this repo:** `Contracts` (I1–I13 and the §12 composite — ported with
its tests, D7), `Gate`, `eval/`, `assets/`.

**Deleted:** every Apple framework in §1's table. Vision, PDFKit,
FoundationModels, DataDetection, CoreGraphics/CoreText.

### 6.1 Why Docling and not a better OCR engine

`progress-tracker.md`, flagship EPA label page 34: **186 numbers in the file, 1
survives OCR** — the page number. The tracker already ruled out every
recogniser-level cause (not the table API, not the pixels, not DPI, not caught
by the confidence gate, since an unemitted line has no bbox). *"Whole-page
layout analysis is what drops them."*

So the defect is layout, not character recognition, and swapping recognisers
moves CER by single digits and 186→1 not at all. Docling is a layout-aware
parser, which is the tier the failure is actually in. It also collapses D5's
router, `Raster`, `OCR` and the `.docx`/`.xlsx` path into one dependency.

The cloud parsers on the market — Textract, Google Document AI, Azure, ABBYY,
LlamaParse — are disqualified before accuracy is discussed: offline-first.

### 6.2 Two things to measure, not assume

| # | Measurement | What it decides |
|---|---|---|
| M1 | Docling on page 34 — digits recovered vs `pdftotext` | 186 back → the port is a shell swap. 1 back → the problem is not tooling and §6 needs re-planning |
| M2 | Does Docling's export carry per-element bboxes? | **I2** (quote is a substring of the transcript) and click-to-jump both need positions. No positions → §5's "model proposes, span verifies" has nothing to verify against |

**§12 needs recalibrating.** The confidence composite was fitted to Vision's
confidence numbers. Carried over unchanged onto a different parser's scores, it
is a ring that lies.

### 6.3 Order

1. M1 — the Docling spike. Everything below assumes it wins.
2. Port `Contracts` **with its test suite** (D7). Nothing after this is checkable
   until the invariants are.
3. Router + Docling behind a CLI: `doc-read file.pdf --json`, keeping the shape
   `scripts/cli-contract.sh` asserts — `eval/` already parses it, so `eval/`
   becomes the port's regression suite for free.
4. `Findings` as validator (D6).
5. `Gate`, then `Export`.
6. `web/` against the CLI over localhost — one FastAPI file, three routes: open,
   read, ask.
7. Tauri wrapper.

Steps 1–6 already run on macOS, Linux and Windows through a browser. Step 7 is
packaging, not portability.
