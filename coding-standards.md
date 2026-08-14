# Coding Standards — Government Document Reader

How code gets written here. Product definition: `context/project-overview.md`.
Stack and boundaries: `context/architecture.md`. Status: `context/progress-tracker.md`.

Naming and API shape follow the
**[Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)**
— for Swift literally, for Python in spirit (§3). Read them once; they are the
tiebreaker for any naming argument.

Every rule below is written to be checkable — by a test, a grep, or a diff. If a
rule can only be checked by taste, it isn't a rule, it's a preference.

---

## 1. Architecture — layers, one direction

Five layers. **Imports point down only.** No layer imports a layer above it, ever.

| # | Layer | Source root | What lives here | May import |
|---|---|---|---|---|
| 0 | **Contracts** | `Sources/Contracts/` | `Line`, `Finding`, `Confidence`, `Region`, `Urgency`, `ValidationRule` + result types, thresholds | nothing project-local |
| 1 | **Tools** | `Sources/Tools/` | `ocr`, `listFormFields`, `detectData`, `validate(_:using:)`, `cropRegion` — deterministic, no network | 0 |
| 2 | **Agent** | `Sources/Agent/` | planning loop, page selection, chunking, map-reduce over findings | 0, 1 |
| 3 | **Gate** | `Sources/Gate/` | consent prompt + the *single* egress function to the cloud | 0, 1 |
| 4 | **UI** | `Sources/UI/` | SwiftUI views, consumer + inspector modes | 0, 2, 3 |

**A file's layer is its directory, not a reviewer's judgement.** That makes the
rule mechanical:

```sh
rg -l 'import Vision'      Sources | grep -v '^Sources/Tools/'    # must be empty
rg -l 'URLSession|http'    Sources | grep -v '^Sources/Gate/'     # must be empty
rg -l 'import SwiftUI'     Sources | grep -v '^Sources/UI/'       # must be empty
```

These, plus the root check in §1.0, are `scripts/layers.sh`. Run it before every
commit; move it into CI the day CI exists.

```sh
sh scripts/layers.sh    # exits non-zero naming the offending file
```

### 1.0 The root is an allowlist

A file's layer is its directory — so a file at the **root** has no directory
above it, no layer, and therefore no import rule. That is why the root gets a
an allowlist rather than a judgement call:

| Root holds | Nothing else |
|---|---|
| `Package.swift` (SwiftPM demands it), `.gitignore` | Code with a layer → `Sources/<Layer>/` |
| Entry-point docs: `CLAUDE.md`, `AGENTS.md`, `README.md`, `ai-workflow.md`, `coding-standards.md`, `issues.md` | A prototype that has not earned a layer → `spikes/` |
| `ocr` — the CLI launcher. An *entry point*, not logic: four lines that `exec swift run`. Its layer lives in `Sources/ocr-cli`. | Anything with behaviour worth testing |

`spikes/` is where a measurement lives before its answer is recorded. Each spike
names, in its header, the layer it is destined for and the slice that kills it —
a spike with no death condition is just code at the root with a folder in front
of it. Build artifacts are gitignored, so they are never enumerated.

The fourth check in `scripts/layers.sh` is the enforcement, and it fails naming
the stray file. `ocr.swift`'s layer-1 exemption was the last one granted; it
died when the file became `Sources/Tools/OCR.swift` in F1, and no replacement
grace exists.

Validation is split on purpose and only one way: **rules and result types in
Contracts, the deterministic implementations in Tools.** Agent and UI consume the
shared result types and never re-implement a check.

**Separation of concerns** means each layer has exactly one reason to change:

- A tool that formats a string for display has leaked layer 4 into layer 1.
- A view that decides whether confidence is good enough has leaked layer 0 into layer 4.
- An agent that opens a socket has leaked layer 3 into layer 2. That one is a
  **bug against invariant I1**, not a style issue.

Boundaries A–D and the trust boundary in `architecture.md` §6 are these layer
seams. Keep them where the diagram puts them.

### 1.1 Single source of truth

One fact, one home. Every duplicate is a future disagreement.

| Fact | Its one home |
|---|---|
| Coordinate origin | converted **once** at Boundary A (§8.1 of `architecture.md`). Everything downstream is upper-left. No second conversion, anywhere. |
| Confidence thresholds (escalate point, amber/red) | one `Thresholds` value. Not a literal in a view, not a second copy in the agent. |
| The output contract (`Finding`, `Confidence`, …) | layer 0 types. Tools, agent, UI and tests all use *those* types — no parallel dictionaries, no ad-hoc JSON shapes. |
| Form field list | the PDF's AcroForm widgets, read live. Never cached, never transcribed into a table. The file **is** the ground truth. |
| Decisions and measured numbers | `context/`. Code comments point at it; they do not restate it. |
| OCR engine choice | behind `ocr(image) → [Line]`. Callers never know whether it was Vision or Tesseract. |

If a number appears in two files, one of them is wrong and nobody knows which.

### 1.2 DRY, and where it stops

DRY is about **knowledge**, not about text. Two code blocks that look alike but
change for different reasons stay apart.

- Third occurrence extracts. First and second stay copied. (Two similar things
  are a coincidence; three are a pattern.)
- No interface with one implementation. `ocr(image) → [Line]` earns its abstraction
  because two engines are measured behind it; nothing else here has earned one yet.
- No config for a value that has never changed.
- Before writing a helper, grep for it — `eval/ocr_bench.py` already owns
  `cer()`/`wer()`/`ber()`/`norm()`, and a second normaliser would silently score
  differently from the first.

---

## 2. Naming and API shape (Swift)

Straight from the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).
The rules that bite most often here:

**Clarity at the point of use beats brevity.** The call site is read a hundred
times; the declaration once.

```swift
// yes
let lines = try ocr.recognizeLines(in: pageImage)
gate.escalate(crop: region, reason: .lowConfidence)

// no
let l = try ocr.run(pageImage)          // what comes back?
gate.send(region, 1)                    // 1 what?
```

- **Omit needless words.** `lines(from:)`, not `lineArrayFromImageFile(imagePath:)`.
- **Name by role, not by type.** `crop`, `page`, `deadline` — not `img`, `int`, `str`.
- **Compensate for weak type information.** A bare `CGRect` or `Double` parameter gets
  a noun label: `crop(page:rect:)`, `clamp(confidence:)`.
- **Side effects decide the part of speech.** Mutating/acting → imperative verb
  (`escalate()`, `validate()`); pure/returning → noun phrase (`transcript`, `findings`).
- **Mutating/nonmutating pairs:** `clamp()` / `clamped()`; with a direct object,
  `stripWhitespace()` / `strippingWhitespace()`.
- **Booleans read as assertions:** `finding.isValidated`, `document.hasFormFields`,
  `result.isEscalated` — never `finding.validated`.
- **Protocols:** a noun if it says what something *is* (`OCREngine`); `-able`/`-ible`
  if it says what it *can do*. Acronyms uniformly cased: `OCREngine`, `ocrEngine`, `pdfURL`.
- **Terminology:** use domain terms exactly — *widget*, *AcroForm*, *CER*, *BER*, *NSCER*,
  *restricted-entry interval* mean what the domain says they mean. No invented synonyms
  ("field box", "accuracy score"). No abbreviations a reader can't search.
- **Prefer methods and properties to free functions** unless there is no obvious `self`.
- **Document every declaration** with one summary sentence fragment ending in a period.
  If it's hard to describe, the design is wrong — fix the design, not the sentence.
- **Defaulted parameters go last**, and always carry labels.

## 3. Naming and API shape (Python)

PEP 8 spelling, Swift-guideline philosophy. `snake_case` functions and variables,
`UpperCamelCase` classes, type hints on every public function (the repo already
does: `def norm(s: str) -> str`).

Same rules, translated: role names not type names; booleans as assertions
(`is_validated`, `has_form_fields`); imperative verbs for side effects
(`write_report`) and noun phrases for pure returns (`transcript`); module
docstring says what the file is *for* and how to run it — `eval/ocr_bench.py` is
the model to copy.

CLI convention, already established, keep it: **answer on stdout, diagnostics on
stderr**, so anything pipes into `eval/score.py`.

Standard library first. `eval/openai_run.py` is stdlib-only on purpose; new
dependencies need a line in `progress-tracker.md` saying what they buy.

---

## 4. TDD — the failing test comes first

Non-negotiable order, per unit of work:

1. **Red.** Write the test. Run it. *Watch it fail, and read the failure message* —
   a test that passes before the code exists is testing nothing.
2. **Green.** Smallest change that passes.
3. **Refactor.** Only with the test green.

Bug fixes are the same loop: first a test that reproduces the bug and fails, then
the fix. A fix without a reproducing test is a fix that comes back.

**The invariant table is the test list.** `architecture.md` §8 (I1–I13) was written
to be executable. No build-order stage is "done" until its invariants have tests.

Note the two numbering schemes are different and both are load-bearing: **stages**
are the build order in `progress-tracker.md` (1–9, the order things get built);
**layers** are §1 above (0–4, what may import what).

| Build-order stage | Architecture layer(s) | Test that must fail first |
|---|---|---|
| 1 OCR | Tools | real scan → JSON with bboxes; a flipped-origin fixture fails (I12) |
| 2 Validators | Contracts (rules) + Tools (impl) | table-driven: known-good and known-bad EPA reg numbers, dates, amounts |
| 3 Output contract | Contracts | a fabricated quote fails the `quote ⊂ transcript` assertion (I2) |
| 5 Composite + gate | Contracts + Gate | a known-bad region scores red and is selected (I3, I4) |
| 6 Egress | Gate | a payload containing anything outside the approved crop set fails (I1) |

Rules:

- Test **behaviour through the layer's public surface**, not private helpers.
- **Table-driven** wherever inputs vary and logic doesn't — validators especially.
- Tests state behaviour in the name: `test_relative_deadline_anchors_to_letter_date`,
  not `test_case_3`.
- **The eval harness is measurement, not assertion** — `eval/ocr_bench.py` and
  `eval/score.py` report numbers. Assert only a *floor* (a regression guard), and
  record the number in `progress-tracker.md`. Don't pin an exact score; it will
  flap and get muted.
- Non-trivial logic ships with at least one runnable check. A one-line pass-through
  does not need a test.

---

## 5. Observability

Two audiences: **the inspector mode** (a product feature — it proves the agent is
real) and **you at 3am**. Same log stream feeds both.

### 5.1 What gets logged

Every tool call and every agent step, one structured line, stderr:

```text
step=4 kind=tool     tool=ocr_page  ms=412  ok=true  page=12 lines=87 conf_p50=0.61 conf_min=0.09
step=5 kind=tool     tool=escalate  ms=1830 ok=true  crop=p12:r3 bytes=18244 consent=granted reason=low_confidence
step=6 kind=decision agent=plan     ms=3    ok=true  pages_selected=[1,2,12] tokens_in=812 reason=rate_table_detected
step=7 kind=failure  tool=ocr_page  ms=88   ok=false page=13 input_kind=jpeg input_bytes=51204 error=vision_no_document next=mark_unresolved
```

**Required on every entry, no exceptions: `step`, `kind`, `ms`, `ok`.**
`kind` is one of `tool` / `decision` / `gate` / `failure`.

`reason=` is **required** on `decision`, `gate` and `failure` entries — those are
the ones a human asks "why did it do that?" about. On a `tool` entry it's required
only when the call isn't mechanically implied by the current plan (an escalation
is; the fourth page of a sequential read isn't).

Log at minimum:

- every tool call — arguments' *shape*, timing, result size, success/failure;
- every agent decision — which pages, which fields, why;
- every confidence computation — the per-signal breakdown, not just the composite
  (I4 requires it to be *shown*, so it must be *recorded*);
- every gate interaction — what was offered, what the user chose;
- every failure — **the input's safe metadata only** (`input_kind`, `page`,
  `region_id`, `input_bytes`, the error), plus `next=` saying what happened
  (`retry` / `fall_through` / `mark_unresolved`). Never a swallowed error, and
  never the raw input — see §5.2, which the error path is the most likely place
  to violate.

### 5.2 What must never be logged

This is a privacy-first product; the log is the easiest place to break the pitch.

- **No document text, no crops, no page images.** Log `lines=87 chars=2129`, never
  the transcript. Log `crop=p12:r3 bytes=18244`, never the bytes.
- **No API key**, no key prefix, no key length.
- **No filenames and no paths — not even the basename.** A basename is often the
  most identifying string in the whole system (`2024-tax-return-jane-doe.pdf`).
  Use a session-scoped opaque `document_id`; log the extension separately if
  diagnostics need the format.
- **No raw error payloads** — no request bodies, no response bodies, no dumped
  input objects. Log the error *kind*, not the thing that caused it.

Checkable, and this is the enforcement that matters: **the log schema is an
allowlist of keys**, and anything not on it cannot be logged. One end-to-end test
over a fixture asserts (a) every emitted event uses only allowlisted keys, and
(b) no emitted value contains the fixture's transcript text, filename, path, crop
bytes, or credentials.

A length-based check — "no transcript substring longer than N characters" — is
**not** sufficient and must not be used as the only guard: it passes happily
while a document leaks in short fragments, and it says nothing about filenames.

### 5.3 Performance checks

Time every boundary crossing. One helper, used everywhere — not a stopwatch
copy-pasted per call site.

```swift
let (lines, ms) = measure { try ocr.recognizeLines(in: image) }
log(step: n, kind: .tool, tool: "ocr_page", ms: ms, ok: true, ["page": p, "lines": lines.count])
```

Record and watch: OCR ms/page, per-tool-call ms, agent step count per document,
tokens in/out per model call, end-to-end ms per document, peak RSS.

- **Token count is asserted before every model call**, not measured after — I13
  exists because the 4096-token limit fails silently.
- **Bounded loops are logged when they bind**: hitting the chunk cap or the
  per-chunk call cap logs at warning level (I10). A silent cap looks like success.
- **Budgets come from measurement, never from a guess.** Run it, take p50 and p95,
  write them into `progress-tracker.md`, then make the budget a test. This is the
  same rule that settled OCR and mere.run — measure, then decide.
- Any regression >20% against a recorded budget is a bug, not a mystery.

---

## 6. Nitpicks

Small, enforced, non-negotiable.

- **Comments say *why*, code says *what*.** The header of `Sources/Tools/OCR.swift` — "…not
  `VNRecognizeTextRequest` because the older API interleaves the columns into
  nonsense" — is the standard. Comments that restate the code get deleted.
- **Name the design pattern above the implementation.** If a file uses a
  recognised pattern, the comment block on top says which one, *why it was
  chosen*, and what the alternative was. A reader who knows the pattern then
  reads the file in half the time; one who doesn't gets a searchable term.

  ```swift
  // Strategy. `ocr(image) -> [Line]` has two implementations — Apple Vision on
  // macOS, Tesseract everywhere else — chosen at init, invisible to callers.
  // Earned it: both are measured (Vision CER 26.9% / Tesseract 27.8%), and the
  // product must stay portable. Not a plugin system; two cases, one switch.
  ```

  Rules on it: name the pattern by its **established name** (Strategy, Adapter,
  map-reduce, Facade — terminology-well, §2), never a private coinage. Don't
  name a pattern the code doesn't actually implement — a mislabelled Factory is
  worse than no label. And never reach for a pattern *so that* there's something
  to name; the comment documents a decision, it does not justify one.
- **Mark deliberate shortcuts** with a `ponytail:` comment naming the ceiling and
  the upgrade path: `// ponytail: 2-page window, needs real page selection (open Q5)`.
- **No dead code, no commented-out code.** Git remembers.
- **No magic numbers.** A threshold, a page cap, a size limit — named constant in
  layer 0.
- **Errors are named, not swallowed.** Every `catch` either handles, logs and
  degrades, or rethrows. `try?` discarding an error needs a comment saying why the
  failure is acceptable.
- **Fail loudly at the boundary, degrade gracefully in the UI.** §9 of
  `project-overview.md` is the contract: never an empty result dressed as success.
- **Files stay small and named for their layer.** One responsibility per file.
- **No `print` for diagnostics** — use the logger, so inspector mode sees it.
- **Formatting is the tool's job**, not review's: `swift-format` for Swift,
  `ruff` for Python. Nobody argues about line breaks.
- **Commits are imperative and scoped**: `Add bbox origin conversion at Boundary A`.
  One logical change per commit.

---

## 7. On major architecture changes — update `context/`

**Any change to a layer boundary, a contract, an invariant, a dependency, or a
decision that a future reader would otherwise have to reverse-engineer gets a
`context/progress-tracker.md` update in the same commit as the code.**

Major means: a new or removed layer or boundary · a change to the output contract
types · an invariant added, dropped, or weakened · a new third-party dependency ·
an engine, model, or endpoint swap · a build-order change · anything that resolves
or reopens one of the **Open — needs a decision** questions.

What to update, in `progress-tracker.md`:

1. **Build order** table — status of the affected layer.
2. **Decision log** — one row: the decision, and whether it came from *yours*,
   *mine*, or *measurement*.
3. **What measurement settled** — if the change came from numbers, the numbers go
   here, with how they were produced.
4. **Open — needs a decision** — remove what's now answered, add what's now open.

If the change alters the stack, the boundaries, the storage model, or the
invariants, `architecture.md` changes too — and the tracker gets the pointer.
`context/` is the single source of truth for *why*; a PR that changes the why
without changing `context/` is incomplete.

---

## 8. Review checklist

- [ ] Failing test existed first, and its failure message was read.
- [ ] Every invariant this code touches has a test.
- [ ] Imports point down only; no layer skipped upward.
- [ ] Nothing duplicated that already has a home (§1.1).
- [ ] Names read as English at the call site; booleans are assertions.
- [ ] Every declaration has its one-sentence doc comment.
- [ ] Any design pattern used is named and justified above the implementation.
- [ ] Every log entry carries `step`, `kind`, `ms`, `ok`; decisions, gate steps
      and failures also carry `reason=`.
- [ ] Log keys are allowlisted; no document text, crop bytes, filename, path or key.
- [ ] Deliberate shortcuts carry a `ponytail:` comment.
- [ ] `context/progress-tracker.md` updated if §7 applies.
