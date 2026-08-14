# Progress Tracker — Government Document Reader

The only file that changes constantly. Current phase, what's measured, what's
decided, what's still open.

Product definition: `context/project-overview.md`.
Stack and boundaries: `context/architecture.md`.
How code gets written: `coding-standards.md` — §7 of it requires this file to be
updated in the same commit as any major architecture change.

---

## Current phase

**Spikes done, nothing built.** Every open question that could be answered by
measurement has been measured. Layer 1 of the build order has not started.

---

## Build order

Layers, inside out. Each tested before the next starts. Layers 1–3 have no model
dependency, so they're testable now.

| # | Layer | Done when | Status |
|---|---|---|---|
| 1 | `ocr.swift` emits regions + confidence as JSON | Real scan → JSON with bboxes, asserted in a test | spike works, no test |
| 2 | Format validators (EPA reg no., dates, amounts, form numbers) | Table-driven test over known-good and known-bad strings | not started |
| 3 | Output contract types + `quote ⊂ transcript` check | A fabricated quote fails a test | not started |
| 4 | Local extraction → findings | Tier 1 + tier 2 filled on the EPA fixture, no cloud call | not started |
| 5 | Confidence composite + gate | Known-bad region scores red and is selected for escalation | not started |
| 6 | Crop + cloud escalation + merge | Only selected crops leave; merged result marked escalated | not started |
| 7 | Consumer UI | The three demo fixtures render correctly | not started |
| 8 | Inspector UI | Step log, signals, escalations all visible | not started |
| 9 | Ask/skip branch | Skip still produces a rendered result | not started |

---

## What measurement settled

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
| **mere.run ruled out** — needs 16 GB memory headroom on a 16 GB machine; measured, reproducible | measurement |
| **RapidOCR rejected** — NSCER 47.6% vs Apple's 26.2%; Chinese recogniser can't read English gov docs | measurement |
| **OCR: Apple Vision on macOS, Tesseract as portable fallback** — behind one `ocr(image) → [{text, confidence, bbox}]` contract | measurement |
| **Agent is model-agnostic** — one OpenAI-compatible client, swappable base URL | yours |
| **Template-only mode withdrawn** — a no-model pipeline misses the AI-agents theme and 25% of the rubric | mine, corrected |
| **Deterministic tier reframed as the agent's tools**, not a replacement for the agent | mine |
| Portable tool layer: PyMuPDF/pdfium for PDF+forms, Presidio for future masking | mine |
| Apple Intelligence is optional, not foundational — device IS eligible (`appleIntelligenceNotEnabled`, not `deviceNotEligible`) | measurement |

---

## Repo state

Superseded, safe to delete:

| Path | Why |
|---|---|
| `spike.py` | Written before any spec; assumes a cloud-first model and a fixed schema. Both void. |
| `fixtures/` | Synthetic letters. `assets/` + `degrade.sh` are real documents degraded realistically — strictly better. |
| `agent.py`, `app.py`, `index.html` | Field Log prototype. Worth reading once for the bounded-loop and evidence-quote patterns, then delete. |

Keep: `assets/`, `ocr.swift`, `ocr`, the `spike_*` binaries, `eval/`, `context/`.

`eval/` now holds the full measurement harness — `ocr_bench.py` (any engine, four
metrics, `--compare`), `engines/rapidocr_run.py` (portable OCR, plain-text and
`--json` modes matching `ocr.swift`'s shape), `cases.json` + `score.py`
(reasoning-model scoring with deadline-anchor traps), `openai_run.py` (any
OpenAI-compatible endpoint).
