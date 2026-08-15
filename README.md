# PigeonEye

<<<<<<< HEAD
Government document reader. Context lives in [context/](context/) — [project-overview.md](context/project-overview.md), [architecture.md](context/architecture.md), [progress-tracker.md](context/progress-tracker.md).
=======
Open a confusing government document and get back what it says, what it
obligates you to do, and how sure the app is about each value — with every
claim quoted from the source. A native macOS app, no server, no account, no
model download.

Built for farmers and farm operators reading EPA pesticide labels, IRS farm tax
forms and NRCS conservation paperwork — documents where missing one line costs
money or legal standing.

Two properties carry the product:

1. **Nothing leaves the machine unless you say so.** On a machine with a local
   reasoning model, nothing leaves at all. Without one, the app falls back to a
   configured OpenAI-compatible endpoint — and tells you so *at import*, before
   anything is read. A fallback you have to discover is a lie.
2. **It tells you where it's unsure.** Every value carries a confidence reading
   and the verbatim words it came from. A confident wrong date on a regulatory
   document is worse than no date.
>>>>>>> ea771a4 (F8 export and the findings index, as they stood)

## Run it

```sh
<<<<<<< HEAD
swift build && swift run PigeonEye
swift test                    # ~45s
sh scripts/layers.sh          # layer + root-cleanliness checks — before any commit
```

Reading a document is entirely local and needs nothing configured. **Asking a
question about a page** is the one thing that leaves the machine, and it needs a
key:

| Variable | Default | |
|---|---|---|
| `OPENAI_KEY` or `OPENAI_API_KEY` | — | without one the ask panel says so and shows no field |
| `OPENAI_BASE_URL` | `https://api.openai.com/v1` | any OpenAI-compatible endpoint, including a local one |
| `OPENAI_MODEL` | `gpt-4o-mini` | |

Nothing reads `.env` — export it, or pass it on the command line:

```sh
OPENAI_KEY=sk-… swift run PigeonEye
```

`⌘K` puts the caret in the ask box; `?` lists every shortcut.
=======
swift build                       # the app and the ocr CLI
swift run PigeonEye               # opens the reader window
swift test                        # ~25s
```

Requires macOS 26+ and Swift 6.2. Zero third-party dependencies — PDFKit,
Vision and SwiftUI all ship with the OS.

`./ocr <file…>` is the same OCR tier as a CLI, `--json` for machine-readable
output. It's a tracked launcher script, not a binary — don't `cp` a build
product over it.

## What works today

| | |
|---|---|
| Import | PDF, PNG, JPEG · ≤20 MB · ≤120 pages |
| Read | every page rasterised at 150 dpi and OCR'd through Apple Vision, with per-line confidence and bounding boxes |
| Form mode | decided by the file — if a page carries a fillable widget, the field list is read straight out of the AcroForm. Ground truth, nothing inferred |
| Findings | values that matter, each with the quote it came from, a page reference and a confidence ring |
| Transcript | the full text it read, collapsible |
| Export | JSON, CSV, plain text or PDF, to a path you pick. Findings and fields only — never document bytes |
| Inspector | ⌘I — every step it took |

Not built yet: the explanation tier (summary, urgency, next steps), the
consent gate for escalating unclear crops, and honest-failure rendering.
`issues.md` has the feature list; `context/progress-tracker.md` has the status.

### Keyboard

`⌘O` open · `⌘←/⌘→` page · `⌘−/⌘+` zoom · `⇧⌘T` transcript · `⌘I` inspector ·
`?` the full list.

## Layout

A file's layer is its directory, and imports point down only.

```
Sources/Contracts/   0  types, thresholds, limits — no dependencies
Sources/Tools/       1  OCR, rasterise, AcroForm, crop, validators, export
Sources/Agent/       2  the read loop and what it chooses to read
Sources/UI/          4  SwiftUI reader, inspector, onboarding
Sources/ocr-cli/        the ./ocr executable
eval/                   Python measurement harness — any OCR engine, four metrics
assets/                 real EPA / IRS / NRCS documents, plus degraded scans
spikes/                 prototypes that have not earned a layer
web/                    the landing page (Next.js) — see web/README.md
```

The root is an allowlist: entry-point docs and `Package.swift`, nothing else.

```sh
sh scripts/layers.sh          # layer + root-cleanliness checks — run before any commit
sh scripts/cli-contract.sh    # ./ocr --json still has the shape eval/ parses
```

## Docs

`context/` is the source of truth for *why*. A change that alters the why
without changing `context/` is incomplete.

| File | Answers |
|---|---|
| [context/project-overview.md](context/project-overview.md) | What the product is, who it's for, what it will **not** do |
| [context/architecture.md](context/architecture.md) | Stack, boundaries, invariants I1–I13, output contract, confidence composite |
| [context/progress-tracker.md](context/progress-tracker.md) | Current phase, what measurement settled, open decisions, decision log |
| [issues.md](issues.md) | The eight features and their slices |
| [context/features/](context/features/) | One spec per feature, written before the code |
| [context/coding-standards.md](context/coding-standards.md) | How code is written here |
| [ai-workflow.md](ai-workflow.md) | How an agent works here — one slice at a time |

## What measurement settled

Numbers, not preferences — full working in the progress tracker.

- **Apple Vision is the local OCR tier.** 26.9% CER / 20.1% BER over 18 degraded
  scans; Tesseract within a point on CER but clearly worse on words; RapidOCR
  rejected at 47.6% NSCER — it ships only a Chinese recogniser.
- **Vision's *low* confidence is trustworthy, its high confidence is not.** The
  four highest-scoring lines in the corpus were checkbox artifacts read as CJK
  glyphs. So low confidence triggers escalation, but high confidence alone never
  awards green.
- **OCR loses rate tables.** Numeric recall runs 74–100% per document; on the
  woody-brush table of the flagship EPA label, 1 of 186 numbers survives. A line
  Vision never emitted has no bbox and no confidence, so the gate cannot catch
  it — the open fix is to take *values* from the text layer and keep OCR for
  geometry and confidence.
- **mere.run is ruled out on this hardware.** It wants 16 GB of admission
  headroom on a 16 GB machine. Reproducible, not a preference.
>>>>>>> ea771a4 (F8 export and the findings index, as they stood)
