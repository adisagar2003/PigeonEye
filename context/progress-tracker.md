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

**F9 slice 9.1 is `complete`, and it was taken out of order — on request.** The
reader can ask a question about the page in front of them and get an answer
grounded on that page, with the model able to fetch other pages it was not
shown. It is a new feature, not a slice of an existing one: `issues.md` had no
chat anywhere, and the only "ask" in it was F5's crop consent.

**Three things this row changed that no later row gets to change back:**

1. **Layer 3 exists.** `Sources/Gate/Gate.swift` is the first and only file in
   the package that holds a socket. Until it landed, the no-network claim was
   the absence of an API — checkable with one grep. It now rests on that file
   being short enough to read in full, and on `scripts/layers.sh` keeping
   `URLSession` out of everywhere else.
2. **Two claims in the UI stopped being true and were changed in the same
   diff.** The header said "Reads locally" unconditionally and the inspector
   said "Left this machine: nothing". Reading *is* still entirely local — the
   rasterise/OCR/findings path touches no network — but asking is not, so the
   header now names the host once a grant is given and the inspector renders a
   ledger of what left.
3. **F5's egress work is partly done.** Slice 5.2's acceptance criterion
   `rg 'URLSession|http' Sources | grep -v '^Sources/Gate/'` is empty and stays
   empty. What 5.2 still owes is the *crop* egress and the approved-set
   assertion; the config, transport seam and failure handling are built.

**What it does not do**, deliberately: no `Finding` is ever minted from a chat
answer. `Finding`'s initialiser is `package` and `Tools.finding(...)` is the one
construction point that checks the quote against the transcript (**I2**). Chat
prose is prose — it is rendered as an answer, never promoted into the findings
list, so I2 is untouched rather than weakened.

**F3 slice 3.2 is `in progress`.** F2 slice 2.1 is complete: the mode is decided
by the file, and a form's field list is read straight out of the AcroForm with
page and rect (`features/02-form-mode.md`). Slice **2.2** (human labels for
cryptic IRS field names) is deliberately deferred — see the decision log.

The current row is **3.2 · a confidence ring that can't lie**
(`features/03-findings-you-can-trust.md`): the composite from
`architecture.md` §12 and the ring that renders it. Slice **3.1** is complete —
format validators and Vision's data detectors, each finding carrying value,
quote, page, region and origin, with **I2**'s substring check at the single
construction point.

F1 is built, reviewed and corrected. The app opens a PDF or a scan, renders it,
OCRs every page and shows the transcript — locally, with no Gate layer in the
package at all. 21 tests pass.

A review of the merged F1 found four defects, all of them in behaviour
`features/01-read-it-locally.md` §7 had already specified and no test covered.
Each now has the test that was missing (§ "F1 review" below).

**The product now has one way in: `Open…`.** The two demo fixture buttons are
removed (Decision log, last row). With them went the last `#filePath` in
`Sources/` — `rg '#filePath|#file' Sources` is empty, and the app no longer
needs the source tree to exist at runtime. That was the standing blocker on
ever shipping this as a signed `.app`, and it is now gone. `assets/` is
unchanged and still feeds the tests and `eval/`.

---

## Build order

**Vertical slices, not layers.** The old table was horizontal — nothing rendered
until stage 7. The working order is the feature list in `issues.md`, and each
feature has a spec under `context/features/`. One source of truth, per
`coding-standards.md` §1.1.

| # | Feature | Spec | Status |
|---|---|---|---|
| F1 | Read it locally | [`features/01-read-it-locally.md`](features/01-read-it-locally.md) | **complete** |
| F2 | Form mode | [`features/02-form-mode.md`](features/02-form-mode.md) | **partial** — 2.1 complete, 2.2 deferred |
| F3 | Findings you can trust | [`features/03-findings-you-can-trust.md`](features/03-findings-you-can-trust.md) | **in progress** — 3.1 |
| F4 | Explain it | — | not started |
| F5 | Escalate with consent | — | not started |
| F6 | Fail honestly | — | not started |
| F7 | Inspector mode | — | partial (step log shipped in F1; the egress ledger shipped in F9) |
| F8 | Export | — | not started |
| F9 | Ask about this page | — | **complete** — 9.1, built out of order (see Current phase) |

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

### F1 second pass — what driving the app found that reading it did not

Every row below came from opening the window and using it. None of them was
visible in a diff, and none had a test. The F1 lesson repeats one level up:
**a build that has never been run by hand is not a build that is known to work.**

| Defect | Was | Now |
|---|---|---|
| Buttons only clicked on the glyph | `.buttonStyle(.plain)` hit-tests drawn pixels only, so the padding inside a bordered label was dead space | One `Flat` style applying `contentShape(Rectangle())`, used by all seven buttons |
| The transcript froze the window | One `Text` holding ~130 KB; SwiftUI lays all of it out in a single pass | `LazyVStack` of per-page `Text`s. **Not** a threading fix — text layout cannot leave the main thread, so a background task would have moved the ~1 ms join and kept the freeze |
| Re-opening the open document re-read it | ~15s, a blanked pane, identical bytes — reachable from one keystroke | `open` latches on **path + modification date**; a re-save is still re-read, an identical request is declined *and says so on screen* |
| ⌘1/⌘2 stole the platform's tab shortcut | Fixture buttons bound to ⌘1/⌘2; a reflex keystroke replaced the open document with a demo one | Fixture buttons have no shortcut. Transcript moved to ⇧⌘T for the same reason — `WindowGroup` gets native tabbing, and ⌘T is New Tab |
| A blank page vanished from the transcript | Empty page transcripts rendered as nothing, so the text of page 12 appeared where page 11 should be | An explicit `— page N could not be read —` marker, distinct from `no text on this page` |

**"Bad scan" was not a bad scan, and the seal misread is not scan damage.** The
button opened `assets/scans/007969-00242-20170111-01.jpg`, which is a clean
digital render. The `WEAL PROTECTED` reading at conf 0.062–0.08 recorded above
is real, but it comes from the **circular seal** — curved text on a logo — and
would happen on a pristine file. It is not evidence about degradation, and the
test named `ocr_reads_a_degraded_scan` was running against that clean page, so
it asserted nothing about degradation and was green for the wrong reason.

Measured on the real thing, `assets/scans/007969-00186-20080911-01.jpg` — a
photocopy with speckle, skew, a `SEP 11 2008` stamp and handwritten annotations:

| | |
|---|---|
| Lines read | **36** |
| Mean confidence | **0.562** (the clean page: 0.627) |
| Below `Thresholds.escalate` (0.45) | **6 lines** |
| Seal fragments | `ANTED STATES` 0.34, `AGENO%` 0.26, `VIAL PROTECAND` 0.26 |
| Date misread | `9/11/2008` → `9/11/2098` — a plausible wrong answer, which is the dangerous kind |

`ocr_reads_a_degraded_scan` now runs against the degraded photocopy rather than
the clean render: degradation is not uniform down a document, and one good page
proves nothing about the confidence reading on page 39. It asserts floors (≥25
lines, mean < 0.60, at least one line below the escalate threshold) and fails
against the clean page — verified by pointing it back and watching mean 0.627
break the assertion.

`eval/cases.json`, `eval/score.py` and `Fixture.cleanPage` still use the clean
page deliberately: it is the fast one-page image for tests whose subject is not
degradation, and the eval ground truth is tied to it.

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

**Still open: the gate reduces it, it does not close it.** `swift run PigeonEye`
segfaulted again with `VisionGate` in place — same stack, `objc_release` inside
**TextRecognition** on `com.apple.root.user-initiated-qos.cooperative`
(`PigeonEye-2026-08-14-190451.ips`). The gate bounds concurrency; the race is
inside a single request's teardown, so bounding cannot remove it. Treat the
"4 consecutive clean runs" number as a reduction in frequency, not a fix, and
do not let F2 assume OCR cannot take the process down.

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
mode needs OCR at all. That is slice 2.2, deferred.

**What building 2.1 added to those numbers.** Two things the recorded counts hid,
both found by writing the tests rather than by reading the spike output:

- **A widget is not a field.** Schedule F is **89 widgets across 84 fields** —
  five checkbox pairs, where `c1_2[0]` and `c1_2[1]` are the two boxes of one
  yes/no and PDFKit puts the index inside `fieldName`. The first version of
  `checkbox_groups_keep_every_member` asserted that a pair *shares* a name and
  failed: 89 distinct names over 89 widgets. Listing per field would drop one box
  of every pair, invisibly. The list is per widget, and the test asserts 84
  against the name with its trailing index stripped.
- **CPA-1200 carries 3 `Link` annotations** as well as its 105 widgets, so
  filtering on `type == "Widget"` is load-bearing rather than defensive.

Cost: reading the widget list is ~40 ms on the 45-page EPA label — cheap enough
to run before rasterising, so the mode is known before any page is rendered.

**2.2's measurement, decided and not yet taken:** label accuracy is the OCR
confidence of the line each label came from, aggregated over the resolved fields
— not the FUNSD harness this section originally named. FUNSD pages carry no
AcroForm widgets, so scoring against them needs a rig that fabricates
pseudo-widgets from FUNSD's annotation boxes; that is a slice of its own, and the
`ocr_bench.py` corpus globbing would need rewriting with it.

### F3.2 — the homoglyph signal is specific, and that is what makes it usable

Measured over all 1092 lines in `assets/scans/` via `./ocr --json`:

| | lines | share |
|---|---|---|
| Total | 1092 | — |
| Carry *some* candidate disagreement | 1024 | **93.8%** |
| Carry a **homoglyph** disagreement | 8 | **0.7%** |

Worst single page 4.3% (`000524-00549-...-01.jpg`, 2 of 47 lines).

That gap is the measurement behind `architecture.md` §12's ranking: raw
candidate disagreement is "low, too noisy as a binary" because it fires on 15 of
every 16 lines, while the homoglyph filter fires on 1 in 128. A signal that flags
almost everything cannot trigger escalation — F5 would send whole documents, and
escalating everything is a failure rather than caution. `the_homoglyph_signal_
flags_few_enough_lines_to_be_a_signal` holds a ceiling at 15% so a future
widening of the character classes cannot quietly turn the signal back into an
alarm.

**A consequence worth naming before 3.3 picks thresholds:** the corpus maximum
line confidence is **0.885** and the placeholder green cut is **0.85**, so almost
nothing can currently reach green even with a validator pass. That is the right
failure direction — it under-claims — but it means the ring is effectively
two-state until 3.3 measures the real numbers.

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
| 2 | ~~**Demo hardware**~~ — **decided**: the first iteration is cloud-only on the OpenAI key. A local tier stays an *option* behind the same swappable base URL, not a shipping requirement, so demo hardware no longer blocks anything. Slice 4.3 becomes a measurement, not a gate | closed |
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
| **The root is an allowlist, checked by `scripts/layers.sh`** — a root file has no directory, so no layer, so no import rule. Code with a layer goes in `Sources/`, prototypes in `spikes/`, and every spike header names the slice that deletes it | yours, enforced by mine |
| **`eval/` stays Python and stays at the root level** — it is measurement, not a layer, and `assets/golden/` + the four metrics have no Swift equivalent worth writing | mine |
| **Vision request concurrency is bounded in `Tools.ocr`, process-wide** — Apple's TextRecognition crashes releasing a finished request; per-caller bounds compose into no bound | measurement |
| **I2 is enforced at one construction point in `Tools`, not per caller** — a caller cannot invent a quote because a caller cannot build a `Finding` any other way. A quote absent from the transcript yields nil rather than throwing, so one bad line does not cost the page its other findings | mine |
| **First iteration is cloud-only, on the OpenAI key.** A local model tier remains an option behind the same OpenAI-compatible base URL, offered rather than required. Closes open question 2 and turns 4.3 from a gate into a measurement — nothing in F3 or F4.1 changes, because both are deterministic and make no model call at all | yours |
| **Search patterns are looser than validation patterns** — one pattern for both drops `10.5 0Z` (OCR for `10.5 oz`) entirely, so the user is never told the rate exists. Find it and fail it; discarding it is the app deciding for the reader | mine, from the F3 review |
| **`Finding` is `Encodable` with a `package` initialiser** — a public init or a synthesised `Decodable` is a second way in with no transcript to check against, which would make I2 a comment rather than a rule | mine, from the F3 review |
| **Validators whole-match rather than contain** — `R G-2 26-O4871` is a real Vision misread from this corpus, and a containment check passes it the moment any fragment looks like a registration number | measurement |
| **A finding's region is its whole line**, not the matched words — Vision returns per-line boxes and word boxes need a second request. Carried as a `ponytail:` ceiling; F5 crops this region so a tighter box is an upgrade | mine |
| **Form fields get their own layer-0 type, `Field`, not a `Finding`** — `Finding.quote` is non-optional and I2 asserts it is a verbatim substring of the transcript; a widget has no quote, and bending it would make slice 3.1's substring check special-case `acroform` | yours |
| **F2 ships as 2.1 alone; 2.2 (label resolution) is deferred** — F2 is a leaf that unblocks nothing, `issues.md`'s own cut order puts 2.2 third, and the demo beat works with raw IRS names | yours |
| **2.2's accuracy will be measured as the OCR confidence of the line each label came from**, not against `assets/golden/funsd/` — FUNSD pages have no widgets, so scoring there needs a pseudo-widget rig that is a slice of its own | yours |
| **`Document` reports `failedPages` and reads on** — a damaged page costs that page, never the document | consequence of the F1 review |
| **Zoom bound and step live in `Contracts.Zoom`** — the bug was the toolbar's step and the model's arithmetic disagreeing | consequence of the F1 review |
| **Boundary A is deterministic and document-stateless, but not freely parallelisable** — the process-wide Vision gate is part of the contract, so a future caller cannot fan out and rediscover the crash | consequence of the PR #9 review |
| **Every `ReaderModel` state write is guarded by request *and* phase** — `requestID` alone only rejects a different open; a progress event from the current read could still land after `.ready` | consequence of the PR #9 review |
| **`ReaderModel` takes its reader as an init parameter** — the only way to test a completion-order race is to hold the progress handler and call it late. Production always gets `Agent.read` | consequence of the PR #9 review |
| **No demo fixtures in the product.** The two header buttons are gone; `Open…` is the only way a document enters the app. They read as a capability list — two named documents answering "what can this open?" when the answer is `Limits.formats` — and they could not have survived distribution anyway: `repoRoot` resolved them through `#filePath`, a build-machine literal | yours |
| **The reader can ask about the page they are on** — a conversation grounded on one page, not on the document. Sending all 45 pages on every question would make "this page's text is sent" a sentence the app cannot mean | yours |
| **The model may fetch pages it was not shown, through one tool (`read_page`), bounded at `Limits.askHops`** — the answer to "where are the woody-brush rates" is on page 34 while the reader is on page 12, and a reader who already knew which page to turn to would not be asking. On the last hop the tool is withdrawn rather than the turn abandoned, so the bound costs latency, never the answer | yours |
| **The ask grant is per document, taken in the panel before the first question** — the same shape as the import-time grant in `project-overview.md` §4.1, for the same reason: a second prompt after the page text has already gone to that endpoint performs protection rather than providing it | yours |
| **Chat prose never becomes a `Finding`** — `Finding`'s initialiser is `package` and `Tools.finding(...)` is the one place a quote is checked against the transcript. Promoting an answer into the findings list would make **I2** a comment. The answer names its pages instead, so a claim can be checked against the page it came from | mine |
| **`Gate` depends on `Contracts` alone, not on `Tools`** — an egress that can reach `Tools` can read a file, and the single thing this boundary promises is that it cannot. The hop loop therefore lives in layer 4, which is the only layer that sees both the `Document` and the egress | mine |
| **The header chip and the inspector's "left this machine" line are now conditional, not constants** — both were true by construction while no Gate layer existed. A claim that is true of the reading path and quietly false of the asking path is exactly the fallback-you-have-to-discover that `project-overview.md` §3.1 rules out | consequence of F9 |
| **`ShortcutsSheet.opensList` takes `typing:`** — the bare-`?` monitor sees every keystroke in the app, so the moment there was a field to type a question into, "what does ? mean" opened the shortcuts sheet and ate the character. A shortcut that steals characters out of a field is worse than no shortcut | consequence of F9 |

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
