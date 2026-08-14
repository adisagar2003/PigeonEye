# Progress Tracker — Government Document Reader

The only file that changes constantly. Current phase, what's measured, what's
decided, what's still open.

Product definition: `context/project-overview.md`.
Stack and boundaries: `context/architecture.md`.
How code gets written: `coding-standards.md` — §7 of it requires this file to be
updated in the same commit as any major architecture change.
How an AI agent works here: `ai-workflow.md` — one build-order row at a time,
this file moved to `in progress` before the code and `complete` after.

---

## Current phase

**F1 built, reviewed and corrected.** The app opens a PDF or a scan, renders it,
OCRs every page and shows the transcript — locally, with no Gate layer in the
package at all. 19 tests pass. F2 has not started.

A review of the merged F1 found four defects, all of them in behaviour
`features/01-read-it-locally.md` §7 had already specified and no test covered.
Each now has the test that was missing (§ "F1 review" below).

---

## Build order

**Vertical slices, not layers.** The old table was horizontal — nothing rendered
until stage 7. The working order is the feature list in `issues.md`, and each
feature has a spec under `context/features/`. One source of truth, per
`coding-standards.md` §1.1.

| # | Feature | Spec | Status |
|---|---|---|---|
| F1 | Read it locally | [`features/01-read-it-locally.md`](features/01-read-it-locally.md) | **complete** |
| F2 | Form mode | — | not started |
| F3 | Findings you can trust | — | not started |
| F4 | Explain it | — | not started |
| F5 | Escalate with consent | — | not started |
| F6 | Fail honestly | — | not started |
| F7 | Inspector mode | — | partial (step log shipped in F1) |
| F8 | Export | — | not started |

The old stage numbers survive where they are load-bearing: `coding-standards.md`
§4 maps stages to the tests that must fail first, and F1 covers stage 1.

---

## What measurement settled

### F1 — what the build measured

| | |
|---|---|
| **Vision cannot read a PDF** | `./ocr <pdf>` → `invalidImage("Zero-dimensioned image (0.0 x 0.0)")`. Rasterisation is mandatory, not a preference. |
| **Page counts** (`mdls -name kMDItemNumberOfPages`) | EPA labels are 45, 40, 29, 22, 13, 12. Four of six are over 20 pages — long documents are the normal case. |
| **45 pages, render + OCR, end to end** | **23.3s** wall, debug build, 6 pages in flight (`reading_a_pdf_produces_a_transcript_and_a_page_count`). The 14.9s figure below is OCR-only over pre-rendered JPEGs, so rasterisation costs roughly 8s of it. |
| **The origin flip is load-bearing, and now proven** | Reverted to Vision's lower-left origin on purpose: the letterhead read `y = 0.9375` instead of `0.046`, and a crop of the *last* line on the page came back as `"january 11, 2017"` — the mirrored position at the top. That is F5 sending a region the user never approved, and it is caught by one test. |
| **The seal misread reproduces** | `WEAL PROTECTED` at conf **0.08** on `007969-00242-...-01.jpg`, matching the 0.062 recorded below. The low end of Vision's confidence is trustworthy. |
| **The CLI contract survived the move** | `spikes/page_index.py` still reports 45 pages, a 1,426-token index at 32/page against 32,394 tokens of full text — identical to the numbers below. |

### Dry run over all of `assets/` — OCR loses the rate tables

Every document read through the shipping path (150 dpi render → Vision): 9 PDFs
/ 161 pages, plus the 18 scans. The scans reproduce the numbers below exactly
(1092 lines, min 0.05, p05 0.34, median 0.61), so the pipeline is unchanged by
the F1 move.

**Accuracy against `pdftotext`, median per page.** All 161 pages carry a text
layer, so ground truth is free. CER is order-sensitive and misleading here —
BER is the honest column, as it was for forms.

| Document | pages | CER | NSCER | BER | **numeric recall** |
|---|---|---|---|---|---|
| `000524-00529` Roundup PRO | 45 | 0.116 | 0.010 | 0.037 | **73.8%** |
| `000524-00549` | 13 | 0.148 | 0.043 | 0.117 | 87.6% |
| `007969-00186` | 40 | 0.622 | 0.338 | 0.177 | 88.4% |
| `007969-00242` | 12 | 0.539 | 0.414 | 0.095 | 92.5% |
| `035915-00004` | 29 | 0.101 | 0.026 | 0.079 | 98.4% |
| `066330-00424` | 22 | 0.487 | 0.298 | 0.094 | 94.8% |
| IRS 4835 | 3 | 0.998 | 0.976 | 0.045 | 95.3% |
| IRS Schedule F | 2 | 0.650 | 0.364 | 0.376 | 90.8% |
| NRCS CPA-1200 | 3 | 0.530 | 0.223 | 0.349 | 100.0% |

**Numeric recall** — what fraction of the numeric tokens in the file survive
OCR — is the column that matters, because a lost application rate is the
failure this product exists to prevent. The most-often-lost tokens across the
corpus are `1.6` (110×), `0.8` (52×), `2.4` (27×), `3.2` (22×): rates, not page
furniture.

**Where the 26% goes.** Three pages of the flagship label, all rate tables:

| Page | numbers in file | survive OCR | lines | conf < 0.45 | Vision "tables" |
|---|---|---|---|---|---|
| 22 | 25 | 14 | 56 | 10 | 0 |
| 32 | 111 | 34 | 80 | 32 | 1 |
| **34** | **186** | **1** | 55 | 25 | 1 |

Page 34 is the woody-brush rate table. The file says
`Hornbeam, American* | 1.6-4 | 0.8-1.6`; OCR returns `Hornbeam, American*` and
nothing else. The only number that survives the page is the page number.

Four things this is **not**:

1. **Not the table API.** Vision detects the table — 55 rows × 3 columns — and
   returns empty strings for columns 2 and 3. `doc.tables` recovers nothing
   that `doc.text` missed.
2. **Not the pixels.** OCR the right-hand 45% of the same 150 dpi render alone
   and 27 digits come back. Whole-page layout analysis is what drops them.
3. **Not fixable with DPI.** Digits found on page 34 at 150/220/300/400 dpi:
   **2 / 82 / 39 / 2** — non-monotonic. At 220 dpi the rates read correctly
   (`0.8-1.6`, `0.8-1.2`, conf 0.49–0.56) and the label's recall rises to
   78.1%, but NRCS falls 100% → 94.6% and two others also drop. There is no
   single good number.
4. **Not caught by the confidence gate as designed.** Page 34 *is* flagged — 25
   of 55 lines sit below 0.45 — so F5 would escalate. But the lost column has
   no region to crop, because a line Vision never emitted has no bbox and no
   confidence. **The gate escalates what was read badly, never what was not
   read at all.**

**One free signal, though:** a Vision table with wholly empty columns is a
self-declared failure, detectable without a model. That is the cheapest
available trigger for a page-level escalation, and it belongs in F3/F5.

**What it means for "OCR every page, always".** The decision was taken
knowingly, on the grounds that OCR error would be caught by the confidence
gate. On rate tables it is not caught — it is an absence, and absence has no
confidence. Meanwhile every one of these 161 pages carries a text layer that
gives 100% numeric recall for free. The decision is worth re-opening for
*values*, keeping OCR for geometry and confidence.

**Also found:** `./ocr` segfaults intermittently under concurrent Vision
requests — 2 crashes in ~40 runs, not reproducible on demand. The CLI fans out
one request per argument with no bound; `Agent.read` bounds at
`Limits.concurrentPages` (6) and has not crashed across many test runs. The
one-line mitigation is to give the CLI the same bound.

### F1 review — four defects, and what they had in common

Every one was a stress case `features/01-read-it-locally.md` §7 already listed.
The spec was right; the tests stopped short of it. **A stress-test table with no
test behind it is a wish, not a check** — the F2 lesson is to write §7's rows as
tests in the same slice, not to trust the prose.

| Defect | Was | Now |
|---|---|---|
| A slower earlier `open` overwrote the newer document | No request invalidation in `ReaderModel`; opening the 45-page label then the scan left the *label* on screen | A `requestID` generation token, checked after every `await`. Proven by removing the guard and watching the test fail with the label's URL |
| One unrenderable page threw the whole document away | `withThrowingTaskGroup` cancels its siblings and unwinds the read | Non-throwing group, per-page outcome, `Document.failedPages`. Every page fails → still a named refusal |
| `./ocr` missing from a fresh clone | Binary is gitignored; every `eval/` caller needed an undocumented copy | Tracked launcher + `scripts/cli-contract.sh` |
| Zoom did nothing | `delta * 100` inside the sum, so the first click of *either* button clamped to 0.7 and stayed | `Zoom.stepped(from:by:)` in layer 0, one home for the bound and the step |

**The Vision crash is Apple's, and the bound belongs in `Tools.ocr`.** The
intermittent segfault recorded earlier now has a stack: `EXC_BAD_ACCESS` in
`objc_release` inside **TextRecognition**, unwinding a finished request — a
refcount race in the framework, not in this code. It cannot be fixed here, only
not provoked.

The mitigation is a process-wide `VisionGate` actor inside `Tools.ocr`, **not**
a bound in each caller, and the distinction is the whole point: `Agent.read`
already bounded itself to `Limits.concurrentPages`, and two concurrent reads
still put twice that in flight. Per-caller bounds compose into no bound. Measured
after: `swift test` went from crashing roughly 1 run in 3 to 4 consecutive clean
runs, wall clock unchanged at ~24s.

### OCR — Apple Vision is the local tier

`doc.text.lines[]` gives text, `confidence`, `boundingRegion`, corner points,
`isTitle` and `topCandidates(n)`. Plus `paragraphs`, `tables` (real
`rows`/`columns`/`cell(row:col:)`), `lists` and `detectedData`. Measured over
`assets/scans/` — 18 pages, 1092 lines, 3 tables, 7 lists, 59 data-detector
matches.

`detectedData` matters more than expected: `calendarEvent`, `moneyAmount`,
`postalAddress`, `measurement`, `phoneNumber`, `emailAddress`, `link` — deadlines,
fees, offices and **application rates** detected natively, with bounding boxes.
For EPA labels, `measurement` is the field type the whole document is about.

### OCR accuracy — good exactly where it matters

`eval/ocr_bench.py` scores any engine against free ground truth: the PDFs in
`assets/` are born-digital, so `pdftotext` reads them near-perfectly, while
`assets/scans/*.jpg` are the same pages degraded by `degrade.sh`. No hand-labelling.

Four metrics because they fail differently — CER (characters), WER (words,
order-sensitive), **BER** (bag-of-words, order-*insensitive*), **NSCER** (CER with
whitespace stripped, separating misreads from dropped spaces). Over 18 pages /
39,883 chars:

| Population | CER | BER | Verdict |
|---|---|---|---|
| EPA letters (prose) | **1.5 – 8%** | 1.8 – 11% | genuinely good |
| IRS / NRCS forms | 13 – 100% | 3 – 43% | poor on order, mixed on content |
| Length-weighted total | 26.9% | 20.1% | misleading, see below |

Best page `066330-00424-…-02`: CER 0.000. Worst `IRS-4835-…-1`: CER 0.996.

Two caveats that stop those numbers being read wrongly:

1. **CER/WER are meaningless on forms.** `IRS-4835-1` at 99.6% CER but 41.7% BER
   is reordering, not misreading. `pdftotext` emits form content in PDF *object*
   order, so the ground-truth ordering is itself arbitrary. On forms, only BER is
   valid — BER exists to catch exactly this, and it did.
2. **This is the photographed worst case.** `degrade.sh` renders at 100 dpi /
   quality 40 specifically to force the OCR path. A born-digital PDF read
   directly has ~0 OCR error, because you use its text layer.

**The conclusion:** Vision is weakest precisely where OCR is unnecessary. Forms
have fillable fields read straight from the file, so 40% BER on IRS-4835 may cost
the product nothing — while the 1.5–8% CER on letters is the number that bears
weight, and it's good.

### Form mode — fields come from the file

All three form PDFs expose complete `Widget` annotation sets via PDFKit: IRS 4835
63 named fields, Schedule F 89, NRCS CPA-1200 105. The EPA label has 0 across 45
pages. So the mode test is deterministic and the field list is ground truth.

One gap: field *names* vary. NRCS ships human-readable ones ("Application
Date"); IRS ships `topmostSubform[0].Page1[0].f1_04[0]`. IRS-style forms need
**label resolution** — for each widget rect, find the nearest printed text (left,
then above) from the OCR pass. Geometry, not inference. It's the only place form
mode needs OCR at all, and `assets/golden/funsd/` has 50 test forms of ground
truth for it.

### Local reasoning — need much less of it than assumed

`SystemLanguageModel.default.availability` on this machine returns
`unavailable(appleIntelligenceNotEnabled)`. The framework is present and
`spike_fm.swift` compiles; Apple Intelligence is simply switched off — a System
Settings toggle plus a multi-GB asset download, region and language gated.

But the measurements moved the goalposts. Between form fields, Vision
`detectedData` and format validators, **almost every value the product must get
right can be extracted deterministically.** What actually needs a language model
is the prose: the summary and the next-step wording.

So: don't block on it. Build deterministic extraction now, and keep the
explanation tier swappable — Foundation Models where available, any
OpenAI-compatible endpoint otherwise.

**Device eligibility settled:** the reason code is `appleIntelligenceNotEnabled`,
not `deviceNotEligible` — the SDK distinguishes the two, so the hardware is fine
(M4, 16 GB, `en_CA`). It is one System Settings toggle away. Apple Intelligence is
therefore *optional*, not foundational: it becomes the fully-local variant on
capable devices, and nothing depends on it.

#### The agent is the product — this constrains the above

The hackathon theme is **AI agents**, and Agent Design is 25% of the rubric. A
deterministic pipeline with no model is a parser, not an agent: it would miss the
theme and score near-zero on a quarter of the marks. **So the template-only
fallback is not a viable shipping mode** — it was briefly proposed and is
withdrawn.

The reconciliation: the deterministic tier is not a replacement for the agent, it
is **the agent's tools**.

```
TOOLS (deterministic, local, cannot hallucinate)     AGENT DECIDES
classify_document()  → form | document               mode, first move
list_form_fields()   → widgets + page + rect         which fields matter
ocr_page(n)          → lines + confidence + bbox     WHICH PAGES to read
detect_data()        → dates, money, rates, addrs    obligation vs noise
validate(v, kind)    → pass/fail + reason            good enough to show?
crop_region(p, rect) → image crop                    worth escalating?
escalate(crop)       → cloud read     [CONSENT]      ask the user, or skip
ask_user(question)   → answer | skipped              is a question warranted?
```

The agentic decisions are real, not decoration: a **45-page** EPA label fits no
context window, so choosing which pages to read *is* planning; the confidence gate
is a bounded, observable branch; the consent gate is genuine human-in-the-loop.

Why this scores: facts enter only via tools, each carrying a quote and a
confidence — so the agent **structurally cannot fabricate a deadline**. That is the
honesty rubric satisfied by architecture rather than by prompting.

#### Model-agnostic, decided

One OpenAI-compatible `/v1` client with a swappable base URL. Cloud for the demo
(the key exists and tool-calling is reliable); local on capable hardware. This
resolves the "download models" tension: the app detects local availability and
degrades to a configured endpoint — Apple's download is Apple's, and nothing is
bundled.

Caveat for the local path: Foundation Models' **4096-token** context is tight for
an agent loop accumulating tool results. Viable only with aggressive per-step
context trimming, and untested.

### mere.run — ruled out on this hardware

Evaluated properly, then ruled out. **Not a preference — a memory wall.**

`vision ocr` refuses to start: *"only 2.96 GB of reclaimable memory is available;
this workload requires at least **16 GB of admission headroom**."* The machine has
16 GB **total**. Reproducible 2/2. macOS itself holds 3–5 GB, so even with every
app closed the ceiling is ~11–12 GB — 16 GB of headroom on a 16 GB machine is not
reachable. No override flag exists (`--min-pixels`/`--max-pixels` apply only to
the `infinity` backend).

That was the *smallest* option: `lightonai/LightOnOCR-2-1B`, 1B params, bf16,
2.02 GB on disk. `vision-ocr-infinity-pro-int8` is larger; the `glm` backend needs
a separate Python `glmocr` install.

**The implication reaches past OCR.** mere.run's own README recommends
`text-chat-gemma4-12b-4bit` for the 16–23 GB RAM tier. If a *1B* OCR model is
refused at 16 GB headroom, a 12B chat model won't be admitted either — so the
`api serve` reasoning tier, which was the genuinely strong argument for it, is
almost certainly blocked here too. Unproven (would cost a 7 GB pull to confirm)
but strongly implied.

Secondary findings, both real:

- **Does not compile from source** on Swift 6.2.3 / macOS 26.2. Two type-inference
  errors in `Sources/MediaIO/MediaVideoIO.swift`; a 2-line annotation patch made it
  worse (*"compiler unable to type-check this expression in reasonable time"*). The
  **prebuilt signed DMG works fine** (`0.37.0`), so it's consumable as a released
  artifact but not as a source dependency you can pin into your own build.
- **Supply chain** (`Package.swift`): the ML core is `sawfwair/mlx-swift`, a
  **personal fork of Apple's mlx-swift pinned to a commit**, not upstream MLX;
  `swift-onnxruntime` pinned at exactly 1.20.1. MIT, so vendorable — but a
  different risk profile from a first-party framework, not a smaller one.

Cost of establishing this: ~5.8 GB of disk across 4 failed builds, a 264 MB DMG,
a 2.02 GB model pull. Reclaimed afterwards.

**Revisit only if the demo machine has 32 GB+.** The model is already downloaded
and `eval/ocr_bench.py --engine 'mere.run vision ocr {img}'` will benchmark it
unchanged.

### OCR engines — three-way benchmark, portable candidates included

Run because an Apple-only tool layer contradicts a model-agnostic product. Same
18 pages, same ground truth, same metrics. **NSCER** added: CER with all
whitespace stripped, to separate "misreads characters" from "drops spaces".

| Engine | CER | WER | BER | NSCER |
|---|---|---|---|---|
| **apple-vision** | **26.9%** | **28.3%** | **20.1%** | **26.2%** |
| tesseract | 27.8% | 32.7% | 31.6% | 27.5% |
| rapidocr | 54.5% | 85.3% | 97.1% | 47.6% |

**RapidOCR is out, and NSCER is what ruled it out.** It ships only the *Chinese*
PP-OCRv4 recogniser, which emits `26DavisDrive` / `January11,2017` because Chinese
has no inter-word spaces. The hypothesis was that NSCER would land near Apple's,
making it a swap-the-recogniser fix. It came in at **47.6% vs Apple's 26.2%** —
nearly double. Character recognition itself is bad on English government
documents, so the space defect was the lesser problem.

**Tesseract is a credible portable fallback** — within 1 point of Apple on CER,
though clearly worse on BER (31.6% vs 20.1%), meaning it mangles more whole words.
50 MB, installs anywhere.

Worth keeping: both alternatives **beat** Apple on the form pages
(`IRS-4835-1` 0.996 → 0.766 Tesseract / 0.876 RapidOCR; `NRCS-1` improved for
both). That's Apple's reading-order collapse showing. But forms are read via
AcroForm, so the advantage is worth ~nothing to this product.

**Untested**, if a stronger portable backend is ever wanted: RapidOCR with an
*English* recogniser, and PaddleOCR PP-Structure (layout-aware, aimed squarely at
the reading-order weakness). Neither changes the macOS answer.

---

## Evaluation

### Domain ground truth

| Path | Purpose |
|---|---|
| `eval/cases.json` | Two real EPA letters. Every value read off actual OCR output — nothing invented. |
| `eval/score.py` | One scorer, any model. Reads the answer on stdin. |
| `eval/openai_run.py` | Runner for any OpenAI-compatible endpoint — serves both mere.run and OpenAI. stdlib only. |
| `spike_fm` | Runner for Apple Foundation Models. Diagnostics on stderr, answer on stdout, so it pipes into the same scorer. |

The two cases are deliberately opposed: `epa-524-529` requires **nothing** of the
recipient; `epa-7969-242` carries a real obligation **plus** a relative deadline
("18 months from the date of this letter") anchored against a decoy date
("Application Date: October 22, 2015"). A model that invents obligations fails the
first; one that misses them fails the second; one that anchors the arithmetic to
the decoy fails `trap:wrong_deadline_anchor` explicitly, with the reason printed.

Scorer self-checked against a hand-written good answer (12/12) and a hand-written
dangerous answer (10/12, failing the trap on "April 2017"). It discriminates.

Run once Apple Intelligence is on:

```sh
./ocr assets/scans/007969-00242-20170111-01.jpg | ./spike_fm | \
    .venv/bin/python eval/score.py epa-7969-242
```

### Generalisation cover — `assets/golden/`

Public labelled datasets, fetched to answer what 18 synthetically-degraded scans
can't: is the confidence signal calibrated, and does the pipeline hold on
documents it wasn't tuned on. 157 MB as fetched; full detail and licences in
`assets/golden/README.md`.

| Set | Scores | Catches what `assets/scans/` can't |
|---|---|---|
| `funsd/` | OCR, label resolution | Real scanner/fax noise; 50 forms of question→answer linking ground truth |
| `kleister-charity/` | deterministic extraction + validators | Long docs, typed fields, and **97 decoy keys** — hallucination bait at scale |
| `govreport/` | the explanation tier | Whether summaries of government prose are faithful, judged against expert-written ones |
| `cuad/` | obligations and deadlines | Obligation spans labelled by lawyers — the one claim nothing else here labels |
| `nist-sfrs/` | form mode incl. Schedule F | **Not fetched** — >412 MB, 1988 scans; opt in with `./fetch.sh nist` |

Not wired into the harness yet — `eval/ocr_bench.py`'s `cer()`/`wer()`/`ber()` are
reusable as-is, but its corpus globbing is `assets/scans`-specific. Wiring FUNSD
through it is a layer-1 job.

**What none of them cover:** no EPA labels (no public labelled set exists), no
relative-deadline arithmetic, no per-item confidence labels, English/US-UK only.

---

## Open — needs a decision

| # | Question | Why it blocks |
|---|---|---|
| 1 | **UI shell — native SwiftUI or Tauri?** `architecture.md` argues native, but that argument rested on Apple-only AI tiers. With a portable tool layer that premise is gone, so Tauri is now genuinely defensible: you rebuild PDF render + annotation on pdf.js, and get Windows/Linux with no Apple dependency anywhere. Native is still faster for the hackathon. | Decides the whole frontend |
| 2 | **Demo hardware** — this 16 GB Air, or something with 32 GB+? | Decides whether any local model tier is possible at all, and whether mere.run is worth revisiting |
| 3 | **Export format** — Markdown checklist, CSV, or JSON? | Small, but it's the app's only write |
| 4 | **Confidence thresholds** — escalate point, amber/red split | Measure against `assets/scans/` and `assets/golden/`, don't guess |
| 5 | **Page window** — the EPA label is **45 pages**; a 2-page default misses the application rates entirely | Needs a real page-selection strategy, not a constant |
| 6 | **Wording of the import-time disclosure** in cloud tier, and whether declining it leaves a usable offline run or refuses the document outright | It is now the *only* consent moment in cloud tier, so it carries the whole trust story |

Distribution to pick thresholds against: 1092 real lines, min 0.054, p05 0.342,
median 0.606, max 0.885, 377 distinct values. Note the asymmetry in
`architecture.md` §12 — a high score cannot be used to award green.

---

## Decision log

| Decision | Source |
|---|---|
| Named Government Document Reader; government docs and complex documentation generally | yours |
| **Start clean** — do not fork the Field Log prototype | yours |
| Hybrid: local first, escalate only low-confidence crops, with consent | yours |
| PDF and document formats first; no camera capture in MVP | yours |
| Fixed field schema rejected as too rigid for varied documents | yours |
| Urgency: all levels valid, icons + highlighting | yours |
| Transcript included, collapsible | yours |
| Confidence as a radial ring with % tooltip, not discrete states | yours |
| No step log for consumers; dev inspector mode instead | yours |
| Ask-or-skip, like the Claude Code harness | yours |
| Cloud provider: OpenAI key | yours |
| Two families tuned, third degrades honestly | mine |
| Two-tier output contract — universal core + open findings | mine |
| Consequence-based urgency; urgency and confidence kept visually distinct | mine |
| Confidence composite, format validators weighted highest | mine |
| Extraction split in two: deterministic fields, model prose | mine, from measurement |
| Page/size/format limits and degradation behaviour | mine |
| Build order above | mine |
| **Vertical slices replace the layer build order**; features live in `context/features/` | yours |
| **OCR every page, always** — no text-layer shortcut for born-digital PDFs. One pipeline, and the OCR errors it introduces are what the confidence gate exists to catch | yours |
| **PDF, PNG and JPEG** can be imported; images skip rasterisation entirely | yours |
| **SwiftPM, no Xcode project** — `swift build` / `swift test` run headless. No app bundle, so a Keychain in F5 falls back to an env var | yours |
| **The PigeonEye Reader v3 design is a proposal, `context/` is the source of truth.** Where they disagree the design element is not built | yours |
| App named **PigeonEye** | yours |
| Confidence cut-points 0.85 / 0.60 / 0.45 carried as named placeholders in `Thresholds` until open question 3 measures them | mine |
| **mere.run ruled out** — needs 16 GB memory headroom on a 16 GB machine; measured, reproducible | measurement |
| **RapidOCR rejected** — NSCER 47.6% vs Apple's 26.2%; Chinese recogniser can't read English gov docs | measurement |
| **OCR: Apple Vision on macOS, Tesseract as portable fallback** — behind one `ocr(image) → [{text, confidence, bbox}]` contract | measurement |
| **Agent is model-agnostic** — one OpenAI-compatible client, swappable base URL | yours |
| **Template-only mode withdrawn** — a no-model pipeline misses the AI-agents theme and 25% of the rubric | mine, corrected |
| **Deterministic tier reframed as the agent's tools**, not a replacement for the agent | mine |
| Portable tool layer: PyMuPDF/pdfium for PDF+forms, Presidio for future masking | mine |
| Apple Intelligence is optional, not foundational — device IS eligible (`appleIntelligenceNotEnabled`, not `deviceNotEligible`) | measurement |
| **The crop-consent gate is conditional on the reasoning tier** — live per-crop in local tier, absent in cloud tier where consent is taken once at import. Asking to send a crop after the transcript has already gone to the same endpoint is theatre, and reads as false assurance about everything else | yours |
| **Escalations stay visible even with the prompt gone** — every escalated value is marked escalated, and inspector mode still shows what was sent where | mine |
| **The no-network claim is scoped to the local tier, and the tier is disclosed at import** — not in settings, not in a tooltip | yours |
| I1 and Boundary C in `architecture.md` reworded to be tier-conditional; the single-egress-function rule is unchanged in both tiers | consequence of the above |
| **Vision request concurrency is bounded in `Tools.ocr`, process-wide** — Apple's TextRecognition crashes releasing a finished request; per-caller bounds compose into no bound | measurement |
| **`Document` reports `failedPages` and reads on** — a damaged page costs that page, never the document | consequence of the F1 review |
| **Zoom bound and step live in `Contracts.Zoom`** — the bug was the toolbar's step and the model's arithmetic disagreeing | consequence of the F1 review |
| **Boundary A is deterministic and document-stateless, but not freely parallelisable** — the process-wide Vision gate is part of the contract, so a future caller cannot fan out and rediscover the crash | consequence of the PR #9 review |
| **Every `ReaderModel` state write is guarded by request *and* phase** — `requestID` alone only rejects a different open; a progress event from the current read could still land after `.ready` | consequence of the PR #9 review |
| **`ReaderModel` takes its reader as an init parameter** — the only way to test a completion-order race is to hold the progress handler and call it late. Production always gets `Agent.read` | consequence of the PR #9 review |

---

## Repo state

**The root is now an allowlist, and a grep enforces it** (`coding-standards.md`
§1.0, fifth check in `scripts/layers.sh`). Reasoning: a file's layer is its
directory, so a root-level file has no layer and no import rule — the exemption
`ocr.swift` held was the mechanism, and it was spent, not renewed.

Deleted, all of them named as superseded in this table since before F1:

| Path | Why |
|---|---|
| `spike.py` | Written before any spec; assumed a cloud-first model and a fixed schema. Both void. |
| `fixtures/` | Synthetic letters. `assets/` + `degrade.sh` are real documents degraded realistically — strictly better. |
| `agent.py`, `app.py`, `index.html` | Field Log prototype. The bounded-loop and evidence-quote patterns were read out of it first; both live in `Sources/Agent/Reader.swift` and **I2** now. |
| `spike_vision.swift` | Superseded by `Sources/Tools/OCR.swift` — same `RecognizeDocumentsRequest`, plus the I12 flip the spike never did. Its binary went with it. |

Moved to `spikes/`, because each still has a job and none has earned a layer:

| Path | Job, and what kills it |
|---|---|
| `spikes/spike_fm.swift` | Foundation Models runner; `eval/score.py` pipes `./ocr \| ./spike_fm`. Dies at slice 4.3, when the local tier is decided. |
| `spikes/spike_form.swift` | AcroForm field dump. Dies when F2 builds `listFormFields` in `Sources/Tools`. |
| `spikes/page_index.py` | Was `tools.py`. The page index — 45 pages as a **1,426-token** index at 32/page against **32,394** tokens of full text, re-measured after the move. Dies at slice 4.2, when `Sources/Agent` grows chunk selection in Swift. |

Keep: `assets/`, `Sources/`, `Tests/`, `spikes/`, `scripts/`, `eval/`, `context/`,
and `ocr` — a **tracked launcher script** (`exec swift run ... ocr "$@"`), not a
copied binary, because `eval/` and `spikes/page_index.py` invoke `./ocr` and a
fresh clone had nothing at that path. `scripts/cli-contract.sh` checks its
`--json` shape; F1 named that contract in its acceptance criteria and never
checked it.

`ocr.swift` is gone from the root — it moved to `Sources/Tools/OCR.swift` in F1
and its layer-1 exemption died with the move (`coding-standards.md` §1). Its
`--json` output is unchanged except `bbox`, which is now
`[x, y, width, height]` upper-left rather than `[minX, minY, maxX, maxY]`
lower-left. Nothing read `bbox` (checked), and one origin everywhere is **I12**.

Four stale build commands died with it, found by grepping for the deleted
filename rather than by reading: `CLAUDE.md`, `eval/openai_run.py`'s
"build the OCR tool first" exit, `spikes/page_index.py`'s `FileNotFoundError`,
and `eval/engines/rapidocr_run.py`'s docstring all still said
`swiftc -O ocr.swift -o ocr`. **A deletion is not done until the strings that
name the deleted thing are gone too.**

`eval/` now holds the full measurement harness — `ocr_bench.py` (any engine, four
metrics, `--compare`), `engines/rapidocr_run.py` (portable OCR, plain-text and
`--json` modes matching `ocr.swift`'s shape), `cases.json` + `score.py`
(reasoning-model scoring with deadline-anchor traps), `openai_run.py` (any
OpenAI-compatible endpoint).
