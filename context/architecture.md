# Architecture — Government Document Reader

Companion to `context/project-overview.md`. Covers the tech stack (with
justification against comparable local-first AI apps), system boundaries,
storage model, invariants, the output contract, and the confidence composite.
Status and open questions live in `context/progress-tracker.md`.

Provenance tags: **[verified]** measured or read from the SDK in this project ·
**[researched]** from published sources, listed at the bottom ·
**[untested]** assumption, needs a spike.

---

## 1. Recommendation up front

> **⚠️ This section's premise has since changed — read `progress-tracker.md`
> first.** The argument below rests on both AI tiers being Apple-only. The tool
> layer is now deliberately **portable** (PyMuPDF/pdfium, Tesseract fallback,
> Presidio) and the agent is **model-agnostic** (any OpenAI-compatible endpoint).
> That removes the premise, so **Tauri is now genuinely defensible** and the UI
> shell is an open decision, not a settled one. Native remains faster to build for
> a 24-hour window; it is no longer the only coherent choice.

**Build the hackathon version as a native macOS app: SwiftUI + PDFKit + Vision
+ Foundation Models. Not Electron. Not Tauri — yet.**

The reason is not taste, it's that both of your AI tiers are already
Apple-only:

| Tier | Chosen | Platform |
|---|---|---|
| OCR | Apple Vision `RecognizeDocumentsRequest` | macOS only, Swift **[verified]** |
| Local reasoning | Apple Foundation Models (recommended) | macOS only, Swift **[verified present]** |

Wrapping macOS-only AI in a cross-platform shell buys you a cross-platform
shell around a macOS-only app. You pay the bridge cost and get none of the
portability. And the two things Tauri/Electron are *for* — a web UI and
cross-platform reach — are the two things PDFKit and macOS-only give you free
or make moot.

**If you want the web UI anyway, use Tauri, not Electron** (§4). That's a
defensible choice; Electron isn't.

---

## 2. What comparable apps actually use

| App | Stack | Model distribution | Why it chose that |
|---|---|---|---|
| **Handy** (your reference) | Tauri + Rust core + React/TS/Tailwind; `transcribe-cpp` / `transcribe-rs` (Whisper GGML/GGUF, Parakeet) **[researched]** | Downloaded on demand from `blob.handy.computer` or HuggingFace **[researched]** | Cross-platform (macOS Intel + ARM, Win x64, Linux x64). Speech models have **no OS-provided equivalent**, so downloading is the only option. |
| **AcroRomi** | Swift 6 + SwiftUI, **zero external dependencies**; PDFKit for render + annotation, Vision `VNRecognizeTextRequest` for OCR, Core Graphics, WKWebView **[researched]** | Nothing to download — OS-provided | Native macOS PDF editing. Closest precedent to your app. |
| **leed_pdf_viewer** | SvelteKit + Tauri, PDF.js **[researched]** | n/a | Cross-platform PDF annotation, privacy-focused |
| **LM Studio / AnythingLLM class** | Electron | Downloaded GGUF | Mature ecosystem, identical rendering, JS all the way down |

**The pattern that matters:** apps download models when the OS doesn't provide
an equivalent. Handy downloads Whisper because macOS has no speech model of
that quality exposed to developers. Your equivalents — document OCR and a small
instruct LLM — **do ship with macOS 26**. AcroRomi is the closer analogue, and
it ships zero dependencies.

So the Handy download pattern solves a problem you only have **if you go
cross-platform**. On macOS-only it's pure cost.

---

## 3. The constraint that shapes everything

**Apple Foundation Models: 4096-token context window. Prompt + output combined.
Fixed — not configurable. [researched]**

Measured against your actual documents **[verified]**:

| Input | Tokens (est.) |
|---|---|
| One EPA label page, OCR'd (2,129 chars measured) | ~530 |
| Two pages (your default `pages_read`) | ~1,060 |
| System prompt + schema instructions | ~300–600 |
| Findings JSON output with verbatim quotes | ~500–1,500 |
| **Total for a 2-page whole-document call** | **~2,400–3,700 — fits, barely** |

A dense IRS Schedule F, or any document past ~3 pages, does not fit. So a
single whole-document call is not the architecture.

### 3.1 What it forces: chunked extraction, and that's fine

Vision already hands you natural chunk boundaries **[verified in SDK]**:
`doc.paragraphs`, `doc.tables` (with `rows`/`columns`/`cell(row:col:)`), and
`doc.lists`. So:

```
per chunk (paragraph / table / list):
    small prompt + chunk text  →  findings for that chunk     (~200-800 tokens)

then:
    map-reduce the chunk findings  →  doc_type, summary, urgency, next_steps
```

Every call sits well inside 4096. This is a better fit for the product than a
whole-document call anyway — `findings` are inherently per-region, and each
finding needs a `region` for crop escalation, which a whole-document call would
have to invent.

**Cost:** many sequential on-device calls. Latency is the risk, not context.
**[untested]**

### 3.2 If Foundation Models proves too weak

Ordered by cost to switch:

1. **Deterministic extraction per family** (anchors + regex + Vision
   `detectedData`) for the fields, cloud for the prose summary. Cheap,
   reliable, doesn't generalise.
2. **llama.cpp + downloaded GGUF** (the Handy pattern). Bigger context, better
   quality, ~2–5 GB download, and you're now bundling a runtime — at which
   point Tauri/cross-platform becomes genuinely attractive.

Note the coupling: **choosing a downloaded model is what makes Tauri worth
it.** These two decisions are one decision.

---

## 4. Electron vs Tauri vs native — the actual scoring

| | Electron | Tauri | SwiftUI native |
|---|---|---|---|
| Bundle | ~80–200 MB **[researched]** | ~2–10 MB **[researched]** | ~10–30 MB |
| Idle RAM | ~150–300 MB **[researched]** | ~30–60 MB **[researched]** | lowest |
| PDF rendering | pdf.js — build it yourself | pdf.js or pdfium-render — build it yourself **[researched]** | **PDFKit `PDFView`, free** |
| Annotation overlay | pdf.js `AnnotationLayer` + custom layer **[researched]** | same | **PDFKit overlay, free** |
| Vision OCR access | Swift sidecar + IPC | Swift sidecar / `swift-rs` / `tauri-swift-runtime`; **Tauri does not abstract this — you build and manage the bridge** **[researched]** | **in-process** |
| Foundation Models access | Swift sidecar | Swift sidecar | **in-process** |
| Cross-platform | yes | yes | no |
| Languages in the build | JS/TS | JS/TS + Rust + Swift | Swift |
| Processes to ship & codesign | app + sidecar | app + sidecar | one |

**Electron is out.** For a privacy-first local app it's the worst of both: the
largest attack surface, 10–20× the bundle, and it still needs the same Swift
sidecar Tauri needs. Its advantages — rendering consistency, mature
auto-update, JS all the way down — are not advantages you're buying anything
with here.

**Tauri vs native** comes down to one question: *do you need Windows/Linux?*

- **No** → native. Three of your requirements (PDF display, annotations,
  native feel) are free in PDFKit, and both AI tiers are in-process.
- **Yes** → Tauri, and accept that you're building a Rust core that does no AI
  work, plus a Swift sidecar, plus pdf.js, plus IPC — and that a
  cross-platform build needs a non-Apple OCR and a downloaded model anyway.

For a 24-hour build with working Swift OCR already in the repo, native wins on
every axis including the one you named — "beautiful interface" is easier when
the PDF viewer and annotation layer are given to you.

---

## 5. Recommended stack

| Layer | Choice | Status |
|---|---|---|
| Shell / UI | SwiftUI (macOS 26) | — |
| PDF display + annotation overlay | PDFKit `PDFView` + overlay view | — |
| Confidence rings, badges | SwiftUI shapes (`Circle().trim`) — no chart library | — |
| Page rasterisation | PDFKit `PDFPage.thumbnail` / Core Graphics (replaces `pdftoppm` in-app) | `pdftoppm` verified for fixtures **[verified]** |
| OCR | **`ocr(image) → [{text, confidence, x0,y0,x1,y1}]`** — Apple Vision on macOS, **Tesseract** portable fallback | both **[measured]**: Vision CER 26.9%/BER 20.1%, Tesseract 27.8%/31.6%, RapidOCR rejected at NSCER 47.6% |
| Geometry + confidence | `doc.text.lines[].confidence` + corner points | in SDK **[verified]** |
| Validators | regex + `detectedData` / `dateparser`/Duckling for portability | not built |
| PDF + form fields | **PyMuPDF** or pdfium (portable) — AcroForm widgets + rects + text layer | **[measured]** 63/89/105 named fields across the three forms |
| Masking *(future)* | **Presidio** — reversible pseudonymisation built in | not built |
| Agent orchestration | One OpenAI-compatible `/v1` client, swappable base URL | **decided** — cloud for the demo, local where hardware allows |
| Local reasoning | Foundation Models, chunked per §3.1 | optional, not foundational. Device eligible **[measured]**, quality **[untested]**. mere.run **ruled out** — 16 GB headroom on a 16 GB machine |
| Cloud escalation | OpenAI vision API, crops only | key not supplied |
| Persistence | none (§7) | — |
| Dependencies | **zero third-party** | — |

Everything above ships with macOS 26.2 / Swift 6.2.3 **[verified]**. No package
manager, no bundler, no runtime to download, no models to download.

That last point is the pitch: **a ~20 MB app that reads your documents with no
network and no downloads.** Handy has to ask for a model download; you don't.

---

## 6. System boundaries

```
┌─ THE MACHINE (one process) ────────────────────────────────────┐
│                                                                │
│  user's file          source.pdf     READ-ONLY, never copied   │
│                            │                                   │
│                            │ PDFKit                            │
│                            ▼                                   │
│  ┌──────────────────────────────────────┐                      │
│  │ PDFDocument  →  page images          │  in memory           │
│  └────┬────────────────────┬────────────┘                      │
│       │ AcroForm widgets   │ Vision (in-process)               │
│       │   ← BOUNDARY F     │   ← BOUNDARY A                    │
│  ┌────▼─────────────┐      │                                   │
│  │ fields (name,    │      │  ground truth from the file:      │
│  │ kind, page,      │      │  no OCR, no model, no gate,       │
│  │ region)          │      │  no confidence, I3 n/a  (§9.1)    │
│  └────┬─────────────┘      │                                   │
│       │       ┌────────────▼─────────────┐                     │
│       │       │ lines: text + confidence │                     │
│       │       │ + bbox · paragraphs /    │                     │
│       │       │ tables / lists           │                     │
│       │       └────────────┬─────────────┘                     │
│       │                    │ validators + chunked FM           │
│       │                    │   ← BOUNDARY B                    │
│       │       ┌────────────▼─────────────┐                     │
│       │       │ findings (label, value,  │                     │
│       │       │ confidence, quote,       │                     │
│       │       │ region, validated)       │                     │
│       │       └────────────┬─────────────┘                     │
│       │                    │                                   │
│       │       ┌────────────▼─────────────┐                     │
│       │       │ CONFIDENCE GATE          │ ← BOUNDARY C        │
│       │       │ consent, shows crops     │  human-in-the-loop  │
│       │       └────────────┬─────────────┘                     │
│       │                    │ SwiftUI state (no IPC)            │
│       │                    │   ← BOUNDARY D                    │
│  ┌────▼────────────────────▼────────────────────────┐          │
│  │ page raster + field list + highlight + findings  │          │
│  └──────────────────────────────────────────────────┘          │
└────────────────────────────┬───────────────────────────────────┘
                             │ ONLY consented crops
                             ▼
                      OpenAI vision API        ← TRUST BOUNDARY
```

| Boundary | Contract |
|---|---|
| **F** form | `pdf → [Field]` where `Field = (name, kind, page, region)`. The AcroForm widgets, read live from the file. **Built** in slice 2.1. Not inference — ground truth — so no confidence, no gate, no escalation, and **I3** does not apply (§9.1). Sits alongside A rather than after it: it needs no OCR, so it runs before any page is rendered and decides the mode. |
| **A** OCR | `image → [Line]` where `Line = (text, confidence, bbox, isTitle, candidates)`. Deterministic, no network, and it keeps nothing about a document between calls. It is **not** freely parallelisable: implementations may hold a process-wide concurrency gate, which retains no document data and exists only to enforce the measured safe number of in-flight Vision requests. |
| **B** reasoning | `[Line] + structure → [Finding]`. Chunked (§3.1). Swappable — this is the §3.2 fallback point. |
| **C** gate | The only place a decision leaves the system. **Local tier:** must render the exact crop set before sending. **Cloud tier:** no per-crop prompt — consent is taken at import for the whole document (`project-overview.md` §4.1) — but the egress function is still the only exit, and every escalation is still recorded and shown. |
| **D** UI | In-process SwiftUI state. Native has no HTTP boundary here — one fewer surface than the Tauri/Electron design. |
| **Trust** | Local tier: crops only. Cloud tier: transcript text + crops, under the import-time grant. Either way: never the source file bytes, never a whole page image. |

**The trust boundary is the product.** Everything else is replaceable.

---

## 7. Storage model

The directive mentioned "hybrid storage with Postgres + Vercel Blob." **That
shape is wrong for this product**, and the objection is not cost or complexity
— it contradicts the core claim:

- Postgres implies a server, which implies documents leaving the machine.
- Vercel Blob is document bytes on someone else's disk — precisely what the
  pitch says never happens.
- No accounts and no cross-session persistence are already non-goals.

Shipping either would make the privacy claim false. The storage model is
**ephemeral, deliberately**:

| Data | Lives | Lifetime | Persisted? |
|---|---|---|---|
| Source PDF | user's chosen path | untouched | read-only, never copied |
| `PDFDocument` / page images | process memory | session | no |
| OCR lines (text, bbox, confidence) | process memory | session | no |
| Findings + confidence | SwiftUI state | session | no |
| Escalation crops | memory; temp file only if the API client demands a path | until sent or discarded | no |
| Cloud responses | merged into findings in memory | session | no |
| API key | Keychain (native) or env var | — | never logged, never rendered |

No database. No cache. No queue. No server. Nothing to GDPR.

### 7.1 The only credible reason to add storage

A "documents I've read" history. When that day comes: **SQLite in
`~/Library/Application Support/`, storing findings and not document bytes** —
local file, single writer, no network, no server. Postgres would only make
sense after abandoning local-first, which is the one thing worth keeping.

---

## 8. System invariants

Each is written to be checkable by a test, not by inspection.

| # | Invariant | Enforcement |
|---|---|---|
| **I1** | Nothing crosses the trust boundary outside the scope the user consented to for *this* document. **Local tier:** approved crops only, per crop. **Cloud tier:** transcript text and crops, inside the import-time grant — never the source file bytes, never a whole page image | Single egress function, whatever the tier; assert the payload is within the granted scope and that a grant exists at all |
| **I2** | Every rendered value traces to a quote that is a verbatim substring of the transcript | Substring assertion per finding; a fabricated quote fails a test |
| **I3** | A finding failing its format validator can never render green | Composite clamps on validator failure |
| **I4** | Confidence is never solely model self-report | Composite requires ≥1 non-model signal; inspector shows the breakdown |
| **I5** | "read pages X–Y of N" is always visible | Rendered unconditionally, never behind a disclosure |
| **I6** | Local results survive any cloud failure | Cloud leg is additive-only; timeout/error/decline all fall through |
| **I7** | The source file is never modified | Read-only open; no write path to the input |
| **I8** | No irreversible or outbound action beyond the consented crop POST | No submission, no email, no form filling |
| **I9** | Nothing survives the session | No persistence path exists (§7) |
| **I10** | The chunk loop is bounded | Hard cap on chunks per document and calls per chunk |
| **I11** | A skipped question still produces a rendered result | Skip marks unresolved and continues |
| **I12** | Bounding boxes are interpreted in one consistent coordinate origin | §8.1 |
| **I13** | No FM call exceeds the context window | Assert estimated tokens < limit before every call; chunk splits on failure |

### 8.1 The coordinate-origin invariant, because it will bite

Vision normalised coordinates default to **lower-left** origin
(`CoordinateOrigin.lowerLeft`); PDFKit and Core Graphics image work is
conventionally **upper-left**. `NormalizedRect.verticallyFlipped()` exists
because of exactly this mismatch **[verified in SDK]**.

Handled inconsistently, crops come out vertically mirrored — you escalate the
*wrong region* to the cloud. That silently breaks I1's intent (you sent
something the user didn't approve) and produces confidently wrong merges.
Convert once at Boundary A, and assert it against a fixture with known text
position.

### 8.2 I13 exists because the limit is silent

4096 tokens is a hard ceiling with no negotiation. Without a pre-call
assertion, an over-long chunk fails at runtime on the one document that
matters. Estimate before calling; split on overflow.

---

## 9. Open risks

| Risk | Impact | Resolve by |
|---|---|---|
| **FM is switched off on this machine [measured]** — `availability` returns `unavailable(appleIntelligenceNotEnabled)` | Blocks 3b entirely until enabled | Enable Apple Intelligence in System Settings, then run `./spike_fm`. Until then treat FM quality as unknown, not "probably fine". |
| FM quality on dense regulatory prose **[untested]** | Forces §3.2 fallback | Spike: 5 chunks from `assets/scans/`, compare against hand-written expected findings |
| FM latency across many chunks **[untested]** | Demo feels slow | Same spike, measure wall-clock per page |
| 4096-token limit is **[researched]**, not verified here | I13's threshold could be wrong | SDK exposes `GenerationError.exceededContextWindowSize` but states no number. Confirm empirically once FM runs. |
| Long documents: the EPA label is **45 pages [measured]** | "first 2 pages" misses the application rates entirely — the whole point of the document | Needs a real page-selection strategy, not a constant. Open question 4 in `progress-tracker.md`. |
| Coordinate-origin mismatch (§8.1) | Wrong region escalated | Fixture assertion at Boundary A |
| Not a git repo | Invariants undefensible without history | `git init` before layer 1 |

**Resolved since this table was first written:**

| Was a risk | Outcome |
|---|---|
| `spike_vision.swift` written but never compiled | **Compiled and run.** `swiftc -O` clean, executed over all 18 scans. |
| Confidence thresholds unmeasured | **Measured** over 1092 lines: min 0.054, median 0.606, max 0.885, 377 distinct values. Full analysis in §12 — including that the *high* end is untrustworthy (`口` glyphs scored the top four values). |
| Vision confidence/bbox availability | **Confirmed present**, plus `tables`, `lists`, `detectedData`, `topCandidates`. |

### 9.1 What the AcroForm finding changes here

**[measured]** All three form PDFs expose complete `Widget` annotation sets via
PDFKit — IRS 4835: 63 named fields, Schedule F: 89, NRCS CPA-1200: 105 (with
human-readable names). The EPA label has 0 across 45 pages.

Two consequences for this document:

1. **It strengthens §1 (native) further.** The form-field list, page indices and
   rects come from PDFKit — the same framework already chosen for rendering. In
   Tauri or Electron this is another pdf.js surface to build.
2. **It adds a boundary.** Form mode is a third extraction tier alongside A and
   B, and it is *ground truth from the file* rather than inference — so it needs
   no confidence, no gate, and no escalation. Invariant **I3** does not apply to
   `origin: acroform` findings; they are exact by construction.

---

## 10. Reversibility

The decision that could turn out wrong is §1 (native vs cross-platform). Keep
it cheap to reverse by holding Boundaries A and B to **pure functions with JSON
contracts**:

- `ocr <image...> → JSON` already works this way **[verified]**
- keep reasoning as `[Line] → [Finding]`, no UI knowledge

A later Tauri port then reuses both as sidecars — the shell changes, the AI
tiers don't. What you must *not* do is thread PDFKit view state or SwiftUI
types through the extraction logic.

---

## 11. Output contract

Two tiers, so the versatile part stays versatile and the testable part stays
testable. A fixed `deadline / fee / office` schema fits a campus letter and falls
apart on an EPA label or a Schedule F.

**Tier 1 — universal core.** Same for every document, typed, validated,
regression-testable across all families:

| Field | Type | Notes |
|---|---|---|
| `doc_type` | string | "EPA labeling notification", "IRS farm profit/loss form" |
| `what_it_is` | string | one sentence, plain language |
| `summary` | list[string] | 3–5 bullets |
| `urgency` | enum | `act_now` \| `soon` \| `informational`, assigned by consequence — not by days remaining, since an EPA label may carry a binding restriction and no date at all |
| `next_steps` | list[string] | concrete actions, no advice |
| `pages_read` | (int, int) | surfaced in the UI unconditionally (**I5**) |
| `findings` | list[Finding] | tier 2 |
| `transcript` | string | full verbatim OCR text |

**Tier 2 — `Finding`.** An open list, populated per document. This absorbs the
variety, so adding a document family never means a schema migration:

| Field | Type | Notes |
|---|---|---|
| `label` | string | named per document: "Restricted entry interval", "EPA reg. no." |
| `value` | string \| null | null when present-but-unreadable |
| `confidence` | float 0–1 | §12 |
| `quote` | string | verbatim words this came from — **I2** asserts it's a substring of `transcript` |
| `page` | int | **1-based, required not optional** — click-to-jump depends on it |
| `region` | bbox \| null | for crop escalation and highlight overlay; one coordinate origin (**I12**, §8.1) |
| `validated` | bool \| null | did it pass a format validator? |
| `origin` | enum | `acroform` \| `datadetector` \| `validator` \| `model` — which tier produced it. Drives §12's green rule, and **I3** doesn't apply to `acroform` (§9.1). |

**Form mode's output is not a `Finding`.** Slice 2.1 added `Field = (name, kind,
page, region)` in layer 0 instead. `Finding.quote` is required and **I2** asserts
it is a verbatim substring of the transcript; an unfilled widget has no quote, so
reusing `Finding` would have meant special-casing `acroform` inside the one
substring check I2 depends on. A form document carries both: `Document.fields`
for what must be filled, `findings` for what was read.

## 12. Confidence composite

A model's self-reported confidence is badly calibrated. If the number in the ring
is just the model saying "90%", the ring is decoration with a number painted on
it — worse than the discrete states it replaces, because it looks quantitative.

Signals ranked by how much they can be trusted, **measured over all 18 scans in
`assets/scans/` (1092 lines)**, not assumed:

| Signal | Trust | Measured behaviour |
|---|---|---|
| **Format validators** | highest | Deterministic. EPA reg numbers (`\d{3,5}-\d{2,5}`), dates, amounts, form numbers, rates+units have known shapes. `524-529` validates; `R G-2 26-O4871` does not. |
| **Vision per-line confidence — low end** | high | Real and useful. The known seal misread `"WEAL PROTEIN"` scored **0.062, 2nd lowest of 1092 lines**. Genuine garbage clusters at the bottom. |
| **Vision per-line confidence — high end** | **do not trust** | The four *highest* scores in the corpus (0.885, 0.828, 0.824, 0.788) were all `口` — checkbox artifacts read as CJK glyphs. High confidence does not mean correct. |
| **Homoglyph disagreement in `topCandidates`** | high, and specific | Caught what confidence missed: `"lan Murphy"` scored a mid-range 0.542, but candidate #2 was `"Ian Murphy"` — the correct reading. `l`/`I`, `O`/`0`, `rn`/`m` are exactly the failure mode on reg numbers, names and dates. |
| **Raw candidate disagreement** | low | Too noisy as a binary — 1024 of 1092 lines have *some* disagreement. Only useful filtered to homoglyph classes. |
| **Model self-report** | lowest | Tiebreaker only, never the sole input (**I4**). |

Two rules follow, and they are **not symmetrical**:

1. **Low confidence is a reliable trigger.** Below threshold → escalate.
2. **High confidence is not a licence to show green.** A ring reaches green only
   if a format validator passed *or* the top candidates agree without a homoglyph
   substitution. Otherwise it caps at amber, whatever the OCR score.

Without rule 2, the corpus's worst garbage (`口` at 0.885) renders as the most
confident finding on the page. The inspector shows which signals produced each
ring.

---

## Sources

- [Handy (cjpais/Handy)](https://github.com/cjpais/Handy)
- [Tauri vs Electron 2026: Bundle Size, RAM, Security and Team Fit](https://www.pkgpulse.com/guides/electron-vs-tauri-2026)
- [Tauri vs Electron 2026: Tauri Wins on Size, RAM, and Speed](https://rustify.rs/articles/rust-tauri-vs-electron-2026)
- [Embedding External Binaries — Tauri sidecar](https://v2.tauri.app/develop/sidecar/)
- [tauri-swift-runtime](https://github.com/Choochmeque/tauri-swift-runtime)
- [Tauri v2 vs Electron after 6 months](https://dev.to/hiyoyok/tauri-v2-vs-electron-after-6-months-of-real-development-my-honest-take-2ic0)
- [leed_pdf_viewer (SvelteKit + Tauri + PDF.js)](https://github.com/rudi-q/leed_pdf_viewer)
- [Render PDF annotations with PDF.js AnnotationLayer](https://www.nutrient.io/blog/pdfjs-native-annotation-layer-forms/)
- [AcroRomi — zero-dependency native macOS PDF editor (Swift/SwiftUI/PDFKit/Vision)](https://rominur.com/AcroRomi_Paper.html)
- [Managing the context window — Apple Developer](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window)
- [Making the most of Apple Foundation Models: Context Window](https://zats.io/blog/making-the-most-of-apple-foundation-models-context-window/)
- [What's new in PDFKit — WWDC22](https://developer.apple.com/videos/play/wwdc2022/10089/)
