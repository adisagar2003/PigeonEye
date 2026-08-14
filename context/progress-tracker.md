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

Three metrics because they fail differently — CER (characters), WER (words,
order-sensitive), **BER** (bag-of-words, order-*insensitive*). Over 18 pages /
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
explanation tier swappable with three implementations behind it — Foundation
Models when available, OpenAI when not, and a template-only fallback that emits
findings with no prose at all. The fallback means a failed model never blanks the
screen.

This also resolves the "download models" tension. `architecture.md` §5 sells
"nothing to download":

- **Reading it as "enable Apple Intelligence"** — the download is Apple's, the app
  just detects unavailability and links to Settings. Pitch survives.
- **Reading it as "bundle a runtime and fetch a GGUF"** — the zero-download pitch
  is gone, and per `architecture.md` §3.2 that's also what makes cross-platform
  worth its cost. One decision, not two.

### mere.run — live candidate for the reasoning tier only

Reconsidered because the open question changed. It was cut when the question was
OCR, where Apple Vision won on measurement. The question now is local LLM
inference.

What argues for it isn't the OCR: **`mere.run api serve` exposes an
OpenAI-compatible `/v1/` endpoint.** That collapses the three-implementation
swappable tier into one client with a configurable base URL — local is
`localhost`, cloud is `api.openai.com`, identical request shape.

| | Detail |
|---|---|
| License / stack | MIT, Swift 6, MLX + vendored llama.cpp |
| macOS floor | 15+ (machine is 26.2 ✅); Linux headless too |
| Models | downloaded on demand, `mere.run model pull` |
| Maturity | 63 stars, 757 commits — active, small |

**Honest counterweight:** not safer, *differently* risky. It trades a known risk
(Apple's model needs a toggle, may be too weak) for an unmeasured one
(third-party runtime, multi-GB pull, unexercised integration).

Supply chain, read from `Package.swift`: the ML core is `sawfwair/mlx-swift`, a
**personal fork of Apple's mlx-swift pinned to a commit**, not upstream MLX;
`swift-onnxruntime` pinned at 1.20.1. MIT means it can be vendored, but "safer
than a first-party Apple framework" is harder to argue having seen the graph.

Build cost so far: cloned 168 MB, `swift build -c release` consumed **~5 GB of
disk** (15 GB → 10 GB free) and needed a resume. Target model
`lightonai/LightOnOCR-2-1B` — 1B params, ≈2 GB, Apache 2.0.

**If adopted: reasoning tier only, keep `ocr.swift`.** Vision is measured working,
needs no install, and supplies the per-line confidence, bboxes, tables and
`detectedData` the whole escalation gate is built on.

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
| 1 | **Download models** — enable Apple Intelligence, or bundle a runtime + GGUF? | Decides the zero-download pitch, and couples to native-vs-cross-platform |
| 2 | **Export format** — Markdown checklist, CSV, or JSON? | Small, but it's the app's only write |
| 3 | **Confidence thresholds** — escalate point, amber/red split | Measure against `assets/scans/` and `assets/golden/`, don't guess |
| 4 | **Page window** — the EPA label is **45 pages**; a 2-page default misses the application rates entirely | Needs a real page-selection strategy, not a constant |

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

---

## Repo state

Superseded, safe to delete:

| Path | Why |
|---|---|
| `spike.py` | Written before any spec; assumes a cloud-first model and a fixed schema. Both void. |
| `fixtures/` | Synthetic letters. `assets/` + `degrade.sh` are real documents degraded realistically — strictly better. |
| `agent.py`, `app.py`, `index.html` | Field Log prototype. Worth reading once for the bounded-loop and evidence-quote patterns, then delete. |

Keep: `assets/`, `ocr.swift`, `ocr`, the `spike_*` binaries, `eval/`, `context/`.
