# F1 · Read it locally

**The user can** pick a government PDF or a scan and see, on their own machine
with no network, everything it says and how much of it was read.

Product: `../project-overview.md` · Stack, boundaries, invariants:
`../architecture.md` · Status: `../progress-tracker.md` ·
How code gets written: `../../coding-standards.md` · Agent rules: `../../ai-workflow.md` ·
Slice list: `../../issues.md`

Design: **PigeonEye Reader v3** (claude.ai/design project
`30f7467f-3b6c-4be0-9f75-1119ee366df1`). The app is named **PigeonEye**.

**Precedence.** `context/` is the source of truth. The design is a proposal for
how the sanctioned product should look, and F1 implements the parts of it that
`context/` already permits. Where the two disagree, `context/` wins and the
design element is simply not built — it is logged in §8 as a proposal, and the
way to adopt it is to change `context/` first (`ai-workflow.md` §3), not to
build it and reconcile later.

---

## 1. Demo

Open `assets/epa-labels/000524-00529-20241120.pdf`. The page renders, page
navigation and zoom work, the header says `read pages 1–45 of 45`, and the
transcript disclosure opens onto text Vision actually produced. No network
call happens at any point.

---

## 2. Settled before writing this

| Question | Answer | Whose |
|---|---|---|
| What does the app read text from? | **OCR every page, always.** Rasterise → Vision, one uniform path. Born-digital PDFs get OCR'd too, and the OCR errors that introduces (`10.5 0Z` for `10.5 oz`) are caught by the confidence gate in F3/F5 rather than avoided. | yours |
| What can be imported? | **PDF, PNG, JPEG.** Vision takes images natively, so the image path is *less* code than the PDF path — it skips rasterisation. | yours |
| How is it built? | **SwiftPM, no Xcode project.** `swift build` / `swift test` run headless, which is what lets an agent iterate without a human clicking Run. No app bundle, so a Keychain in F5 falls back to an env var (`architecture.md` §7 already permits that). | yours |
| What does the UI look like? | **The PigeonEye Reader v3 design**, ported to SwiftUI. | yours |

**Measured while scoping, not assumed:** Vision cannot read a PDF.
`./ocr assets/gov-forms/IRS-ScheduleF-farm-profit-loss.pdf` returns
`invalidImage("Zero-dimensioned image (0.0 x 0.0)")`. Rasterisation is
mandatory, not a preference.

**Page counts, read off the files** (`mdls -name kMDItemNumberOfPages`): the EPA
labels are 45, 40, 29, 22, 13 and 12 pages. "The 45-page label" in
`../progress-tracker.md` is `000524-00529-20241120.pdf`, and four of the six
labels are over 20 pages — long documents are the normal case here, not the
edge.

---

## 3. What is real in this slice, and what is empty

The design draws a full reader. F1 builds the subset that `context/` sanctions
*and* F1 can actually produce, and leaves the rest **hidden** — which is the
design's own behaviour, since every analysis block already sits behind a
conditional (`hasSummary`, `hasFindings`, `hasSteps`, `lowSignal`). Nothing is
faked, and nothing outside `context/` is built.

| Region of the design | F1 |
|---|---|
| Header: wordmark, mode line, Setup, Inspector toggle | real, static |
| Fixture buttons | ~~real — each opens a real file from `assets/`, same as the file picker. Two buttons, not three: **`EPA letter`** → `assets/epa-labels/000524-00529-20241120.pdf`, **`Bad scan`** → `assets/scans/007969-00242-20170111-01.jpg`. The design's third fixture is a university registrar notice, which is out of scope §7 — see §8.5.~~ **Removed after F1 — see the note below this table.** |
| Document pane: filename, pages-read chip, page ‹ ›, zoom − + | **real** |
| The page itself | **real** — PDFKit render at 150 dpi, or the image file directly |
| Transcript disclosure | **real** — Vision output, verbatim |
| Urgency badge, document title, confidence ring | hidden (F3, F4) |
| Findings list, highlight overlay, crop box | hidden (F3, F5) |
| Summary, next steps | hidden (F4) |
| Low-signal block, "read it as a document anyway" | hidden (F6) |
| Escalation dialog | not built (F5) |
| Inspector: step log | **real** — open, render, OCR, timings, `network calls: 0` |
| Inspector: signal bars, "left this machine" | ring signals hidden (F3); "left this machine: nothing" is real and true |
| Export findings footer | rendered, disabled (F8) |
| Onboarding screen | see §8 — not built, blocked on decisions |

**The rule this slice establishes:** a section that has no real data is not
drawn. If that leaves the right rail nearly empty on day one, the rail is
honest, and every later feature fills one block.

> **The fixture buttons were removed after F1 shipped.** The row above is left
> struck through rather than deleted, because it is an accurate record of what
> F1 built.
>
> Two reasons, and the second is the one that settles it.
>
> They were read as a *capability list*. Two named documents in the product
> header answer the question "what can this app open?" with "these two", when
> the answer is `Limits.formats` — any PDF, PNG or JPEG up to 20 MB.
>
> And they could never have survived distribution. `ReaderModel.repoRoot`
> resolved them through `#filePath`, a **compile-time literal** holding the
> path of `ReaderModel.swift` on the build machine. On any other machine both
> buttons resolve to a directory that does not exist and every click draws a
> "Not read" refusal. The `ponytail:` comment on `repoRoot` said as much from
> the day it was written: *"The day this ships as a signed .app, they become
> bundle resources or the buttons go away."*
>
> `Open…` (⌘O) and the welcome screen's "Open a file" were always the real
> import path; they are now the only one. §6 and §7 never asserted the
> buttons, so no acceptance criterion or stress case moves. §8 row 5 — which
> records why there were two and not three — is left as written for the same
> reason as the row above.

### 3.1 Four states the design does not draw

The design shows one state: a document, already read. These four are not
embellishment — without them the app is a frozen window or a blank one.

| State | Why it exists |
|---|---|
| **Welcome** — "Read a document", Open a file, formats and size | The design assumes a document is always loaded. Something has to be on screen before one is. |
| **Reading** — "Reading page 12 of 45" with a bar | 45 pages take ~15s (measured). A window that does nothing for 15 seconds is not a design choice. |
| **Refusal** — the named message from `ReadFailure` | `project-overview.md` §9 requires every unreadable case to say what happened. The design has no refusal state. |
| **Open…** in the header | Replaces the design's `Setup` button, which navigates to an onboarding screen that §8 says is not built. A button that goes nowhere is worse than no button. |

---

## 4. Contract

### 4.1 Targets, which are the layers

`coding-standards.md` §1 — a file's layer is its directory, and here it is also
its SwiftPM target, so the dependency graph enforces it instead of a reviewer.

| Layer | Target | Holds |
|---|---|---|
| 0 | `Sources/Contracts` | `Line`, `Region`, `Page`, `Finding`, `Signal`, `Urgency`, `Origin`, `Thresholds`, `ReadFailure`, `Limits` |
| 1 | `Sources/Tools` | `ocr`, page rasterisation, `crop` — deterministic, no network |
| 2 | `Sources/Agent` | `read(fileURL) -> Document` — orchestrates rasterise + OCR, owns the step log |
| 4 | `Sources/UI` | SwiftUI, design tokens, both screens |
| — | `Sources/PigeonEye` | app entry |
| — | `Sources/ocr-cli` | the CLI, so `spikes/page_index.py` and `eval/` keep working |

Layer 3 (`Gate`) **does not exist yet**, and that is checkable:
`rg 'URLSession|http' Sources` must return nothing.

`ocr.swift` moves from the repo root into `Sources/Tools/`, and its layer-1
exemption dies with the move (`coding-standards.md` §1). The compiled `./ocr`
binary at the root stays — `spikes/page_index.py`, `eval/openai_run.py` and
`eval/ocr_bench.py` all shell out to it — and is refreshed from
`.build/release/ocr` after a build.

### 4.2 Boundary A

```
ocr(CGImage) -> [Line]
```

Pure. No state, no network, no UI knowledge. `architecture.md` §10 depends on
this staying a pure function with a JSON contract — it is what makes a later
Tauri port a re-shell rather than a rewrite.

### 4.3 The coordinate origin, converted once

Vision returns normalised coordinates with a **lower-left** origin. PDFKit and
Core Graphics image work are **upper-left**. Handled inconsistently, crops come
out vertically mirrored and F5 escalates a region the user never approved —
which breaks **I1**'s intent while every count-based test still passes.

`Line.bbox` is `[x, y, width, height]`, normalised, **upper-left**. The flip
happens once, inside `Tools.ocr`. Nothing downstream converts again (**I12**).

### 4.4 Limits

| | |
|---|---|
| Max file | 20 MB, rejected naming the actual size |
| Max pages | 120 — `ponytail:` a cap, not a design. Largest real document is 45 pages. |
| Render | 150 dpi. Measured sufficient; 300 doubles render time for no CER gain. |
| Formats | `.pdf`, `.png`, `.jpg`, `.jpeg` — anything else is a named refusal |

### 4.5 Fonts

The design specifies Barlow and Barlow Condensed, both Google fonts. Bundling
or downloading them contradicts the zero-dependency stack, so headings use the
system font at `.width(.condensed)` and body uses the system font. Same
typographic role, nothing to fetch. If the exact faces matter for the demo,
that is a decision, not a bug.

---

## 5. TDD flow

`coding-standards.md` §4 — red, green, refactor, in that order, and the
failure message gets read. Below is the actual sequence for this slice. Each
row is one red→green cycle; do not start the next until the previous is green.

Test framework is **swift-testing**, which ships with the Swift 6.2 toolchain —
no dependency to add. Fixtures resolve from `#filePath`, not the working
directory, because SwiftPM does not promise you a cwd.

| # | Red — write this test first | The failure you should read | Green |
|---|---|---|---|
| 1 | `ocr_reads_a_degraded_scan` — `Tools.ocr` on `assets/scans/007969-00242-20170111-01.jpg` returns non-empty lines containing "REGISTRATION" | `no such module 'Tools'` | Move `ocr.swift` to `Sources/Tools/`, return `[Line]` |
| 2 | `bbox_origin_is_upper_left` — the page's title line has `bbox.y < 0.5` | `y was 0.93` — Vision's lower-left origin, unflipped, puts the top of the page at the bottom | Flip once, in `Tools.ocr`. **I12** |
| 3 | `crop_of_a_line_reads_back_as_that_line` — crop the topmost line's bbox, OCR the crop, compare | `no such function 'crop'`, then a text mismatch if the flip is wrong in a compensating direction | `Tools.crop(CGImage, Region)`. This is the test that makes **I12** real; #2 alone can pass while mirrored |
| 4 | `every_page_of_a_pdf_rasterises` — `007969-00242` (12 pages) yields 12 images, each ≈ mediaBox × 150/72 | `0 images` | PDFKit render at `Limits.dpi`. Vision cannot take a PDF — measured, §2 |
| 5 | `page_cap_is_computed_not_silent` — table-driven over `pagesToRead(total:)`: 1→1, 45→45, 200→120 with `capped: true` | `200 pages returned, cap not applied` | A pure function. No >120-page fixture exists, so test the function, not a document |
| 6 | `reading_a_pdf_produces_a_transcript_and_a_page_count` — `Agent.read(url)` on the EPA label gives `pages == 45`, non-empty transcript, `pagesRead == "read pages 1–45 of 45"` | `no such module 'Agent'` | Orchestrate rasterise + OCR in a TaskGroup. **I5** |
| 7 | `unreadable_files_are_named_refusals` — table-driven: 0-byte, `.txt` renamed `.pdf`, 25 MB, password-protected → the right `ReadFailure`, and `.tooLarge` names the actual size | a crash, or `unreadable` where `tooLarge` was expected | Guards at the entry point, before any render |
| 8 | `the_source_file_is_never_modified` — hash, size and mtime of the input are identical before and after a full read | mtime moved | Read-only open, no write path. **I7** |
| 9 | `the_step_log_never_contains_the_document` — no log entry contains the filename, the path, or any 20-character substring of the transcript | `entry 3 contains "000524-00529-20241120.pdf"` | Log counts and durations, never content. `coding-standards.md` §5.2 |

**What the F1 review changed about this section.** Four defects shipped, and
every one of them was already written down in §7 below as a case that "must
happen" — with no test behind it. The rows were right; the flow stopped at test
#9 and never turned §7 into assertions. From F2 on, **§7's rows are tests in the
same slice**, not prose to check by hand.

**Checked by review, not by a test**, because a test would cost more than it
catches at this size:

- The three layer greps (`coding-standards.md` §1). They go in
  `scripts/layers.sh` so they are one command, and into CI the day CI exists.
- **I9** — that no persistence path exists. It is the absence of an API; a
  grep proves it, a test cannot.
- **I5**'s *rendering* — that the pages-read chip sits outside every
  disclosure. Test #6 proves the string exists and is right; that it is never
  hidden is a diff you read.

Two rules carried from `coding-standards.md` §4 that bite in this slice:

1. **The eval harness is measurement, not assertion.** The 45-page wall clock
   in §6 gets *recorded in the tracker*, and asserted only as a floor if it is
   asserted at all. Pinning an exact number makes a test that flaps and then
   gets muted.
2. **Behaviour through the public surface.** Test `ocr(image) -> [Line]`, not
   the private Vision plumbing behind it — that plumbing is exactly what
   `architecture.md` §10 wants free to change.

---

## 6. Acceptance criteria

- [ ] `swift build` produces an app that opens `assets/epa-labels/000524-00529-20241120.pdf`
- [ ] Every page is rendered and OCR'd; the transcript disclosure shows Vision's reading-order text
- [ ] `read pages 1–45 of 45` is rendered unconditionally, never behind a disclosure (**I5**)
- [x] Page ‹ › and zoom − + work; the page indicator is truthful — **tested**, `zoom_steps_by_the_delta_it_is_given` and `zoom_clamps_at_both_ends_without_snapping`
- [ ] `.jpg` opens without rasterisation and reads
- [ ] `Line` lives in `Contracts`, bbox upper-left, asserted against a fixture line of known position
- [ ] `rg 'import Vision' Sources | grep -v Tools/` empty · same for `SwiftUI`/`UI` and `URLSession`/`Gate`
- [ ] The source file is opened read-only; there is no write path to it (**I7**)
- [ ] `./ocr --json` still produces the same shape `spikes/page_index.py` expects
- [ ] Nothing persists (**I9**) and no document text, filename, path or key reaches a log (`coding-standards.md` §5.2)

---

## 7. Stress test

| Case | Must happen |
|---|---|
| **Crop round-trip** — crop the bbox of the topmost line on page 1 and OCR the crop | Text equals that line. A vertical mirror survives eyeballing and dies here. This is the one test that makes **I12** real. |
| 45-page label, wall clock | Recorded. OCR alone measured 14.9s on the 45-page label; if the app is 3× that, rasterisation is the problem, not Vision. |
| `assets/scans/*.jpg` at 100 dpi / quality 40 | Lines come back. Degraded is the normal path, not the edge. |
| 0-byte file · `.txt` renamed `.pdf` · password-protected PDF | Named refusal each, no crash |
| 25 MB file | Refused naming the actual size and the 20 MB limit |
| A PDF where page 3 fails to render | Pages 1–2 and 4–45 still read; page 3 reported, not swallowed. **Tested** — `one_unrenderable_page_does_not_lose_the_rest`, against `Tests/PigeonEyeTests/Fixtures/damaged-page-2.pdf`. Every page failing is still a refusal. |
| A 200-page PDF | Caps at 120 and **says so on screen** — a silent truncation reads as "read it all" |
| Open a second file without quitting | Previous document's lines are gone, not merged — **including when the first read is slower and finishes last**. **Tested** — `a_later_open_wins_over_an_earlier_slower_one`. |

---

## 8. Design elements F1 does not build, because `context/` says otherwise

These are proposals the design makes that `context/` has not sanctioned. Under
the precedence rule at the top, **`context/` wins and none of them is built.**
Each stays on this list until someone changes `context/` — a decision, taken
deliberately, per `ai-workflow.md` §3.

Five of them live in the **onboarding screen**, which is why F1 does not build
that screen at all. None of them touches the reader screen.

| # | The design proposes | `context/` says | F1 |
|---|---|---|---|
| 1 | Step 01 offers **Llama 3.2 3B (1.9 GB), Qwen 2.5 7B (4.1 GB), Mistral Nemo 12B (7.2 GB)** with download progress | `architecture.md` §5: "no models to download" is *the pitch*; open question 1 is undecided | Not built. Adopting it answers open question 1 in the "bundle a runtime + fetch a GGUF" direction, and per §3.2 that same choice is what makes cross-platform worth its cost — **one decision, not two.** |
| 2 | "**Hosted by us** — no key, no account" | Decision log: "Cloud provider: OpenAI key"; §7: "No server. Nothing to GDPR." | Not built. A service we operate is a server, an operating cost and a data-protection surface — a different product claim from "your key, your account". |
| 3 | Step 03 takes **reference material** to "sharpen the reading" | `project-overview.md` §8 rules out RAG over corpora; **I9** says nothing survives the session | Not built. Reference material that helps has to persist and be retrieved — the ruled-out feature, arriving through the onboarding screen. |
| 4 | Inspector log reads `text layer found · 2 pages, 3,004 chars` | OCR every page, always (§2) | Log line follows the pipeline, not the design: `OCR page n · mean conf`. |
| 5 | Third fixture is a **university registrar notice** | Scope §7 is EPA labels, IRS farm forms, NRCS CPA-1200 | Dropped to two fixtures. A fourth document family has no ground truth in `eval/cases.json` and no `assets/golden/` cover. |
| 6 | Barlow / Barlow Condensed (Google fonts) | `architecture.md` §5: zero third-party, nothing to download | System font at `.width(.condensed)`. Same typographic role, nothing to fetch. |
| 7 | Confidence words at cut points **0.85 / 0.60** | Open question 3: measure against `assets/scans/`, don't guess | Carried as named placeholders in `Thresholds`, replaced by slice 3.3. Nothing reads a literal. |
| 8 | Prepared analysis prose for each fixture (summary, findings, next steps) | Nothing sanctions showing values the pipeline did not produce | Not shown. Those blocks stay hidden until F3/F4 fill them for real. |

The design remains useful for exactly what it is good at: layout, hierarchy,
the token set, the blueprint frame, and the wording of the parts that *are*
sanctioned — the promises, the pages-read chip, the consent-first framing, the
"findings only, never document bytes" footer.

---

## 9. Out of scope for F1

Form-field detection (F2), findings and validators (F3), confidence rings
(F3), summaries and urgency (F4), the escalation dialog and any egress (F5),
low-signal refusal (F6), export (F8), and the onboarding screen until §8 is
answered.

Not built here even though the design draws them: highlight overlay, crop box,
signal bars, "read it as a document anyway".
