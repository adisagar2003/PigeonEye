# F2 · Form mode

**The user can** open a born-digital government form and get the exact list of
fields they must fill, read straight out of the file — nothing inferred, nothing
to hallucinate.

Product · `../project-overview.md` §6 (two document modes) ·
Stack, boundaries, invariants · `../architecture.md` §6, §8, §9.1, §11 ·
Status · `../progress-tracker.md` ·
How code gets written · `../coding-standards.md` ·
Agent rules · `../../ai-workflow.md` ·
Slices · `../../issues.md` F2

**Precedence.** Where this file and `context/` disagree, `context/` wins.

---

## 1. Demo

Open `assets/gov-forms/IRS-4835-farm-rental-income.pdf`. The header reads
**form · 63 fields**. The rail lists all 63 with their page. Click one and the
page pane jumps to that page and outlines the actual box.

Open `assets/epa-labels/000524-00529-20241120.pdf` — 45 pages, header reads
**document**, no field list. The mode was decided by the file, not by a guess.

---

## 2. Settled before writing this

| Question | Answer | Whose |
|---|---|---|
| What decides the mode? | Any page carrying a `Widget` annotation. Not a heuristic, not a filename, not a page count | `project-overview.md` §6 |
| Where does the field list live? | `Sources/Tools/` — `coding-standards.md` §1 already names `listFormFields` as a layer-1 tool | already settled |
| Does a field carry confidence? | No, and never will. `architecture.md` §9.1: exact by construction, **I3** does not apply | already settled |
| New layer-0 type, or reuse `Finding`? | **New `Field`.** `Finding.quote` is non-optional and **I2** asserts it is a verbatim substring of the transcript; an unfilled widget has no quote, and bending it would force slice 3.1's substring check to special-case `acroform` | yours |
| Scope of this slice | **2.1 only.** 2.2 deferred — see §9 | yours |

Measured while scoping, not assumed — `spike_form.swift`, re-run against the
current fixtures:

```
IRS-4835-farm-rental-income.pdf     pages=3  widgets=63  named=63
IRS-ScheduleF-farm-profit-loss.pdf  pages=2  widgets=89  named=89
NRCS-CPA-1200-conservation-...pdf   pages=3  widgets=105 named=105  (+3 Link annotations)
000524-00529-20241120.pdf           pages=45 widgets=0   named=0
```

Two things the recorded counts hid, both found while writing the tests:

- **Widgets are not fields.** Schedule F is **89 widgets across 84 fields** — five
  checkbox pairs, where `c1_2[0]` and `c1_2[1]` are the two boxes of one yes/no.
  Listing per field drops one box of every pair and the loss is invisible on
  screen. The list is per widget.
- **CPA-1200 also carries 3 `Link` annotations**, so filtering on
  `type == "Widget"` is load-bearing, not defensive.

---

## 3. What is real in this slice, and what is empty

| Region of the design | 2.1 |
|---|---|
| Mode chip in the toolbar | Real — `form · 63 fields` or `document` |
| Field list in the rail | Real — name, page, click to jump |
| Highlight over the page | Real — stroked rect over the rendered raster |
| Human labels for cryptic names | **Empty.** Raw AcroForm names. Slice 2.2 |
| Confidence ring on a field | **Never.** §9.1 — there is nothing to be uncertain about |
| Filling, saving or submitting a field | **Never.** `project-overview.md` §8 and **I8** |

**The rule this slice establishes:** ground truth read from the file does not get
a confidence ring, because a ring would claim there is something to be uncertain
about.

---

## 4. Contract

### 4.1 Targets, which are the layers

| Layer | Target | Holds |
|---|---|---|
| 0 | `Contracts` | `Field` — name, kind, page, region |
| 1 | `Tools` | `formFields(pdf:)`, `region(of:in:rotation:)` |
| 2 | `Agent` | `Document.fields`, `Document.isForm`, one step-log line |
| 4 | `UI` | mode chip, field list, highlight overlay, `ReaderModel.select(_:)` |

### 4.2 The form tier

```swift
public func formFields(pdf url: URL) throws -> [Field]
```

A third extraction tier alongside Boundary A (OCR) and B (reasoning), and unlike
both it is ground truth rather than inference — so it needs no confidence, no
gate and no escalation (`architecture.md` §9.1). It touches no Vision at all,
which also puts it outside the TextRecognition crash the tracker records.

Read live on every call, never cached, never transcribed into a table
(`coding-standards.md` §1.1) — the file *is* the ground truth.

### 4.3 The coordinate origin, converted once — again

`PDFAnnotation.bounds` is PDF user space: origin **lower-left**, unnormalised
points, offset by the mediaBox origin. `Region` is normalised **upper-left**, the
space `Tools.ocr` already converts Vision's corners into (**I12**, §8.1). This is
a *second* space arriving in the same product, and `issues.md` calls a mistake
here "a second I12 bug hiding behind the first one being fixed".

The conversion is a separate pure function precisely because `assets/` has no
rotated page: a table of hand-computed rectangles at 0/90/180/270 is the only
honest check on the quarter-turn cases, and `rasterise` lets PDFKit apply
`/Rotate` to the pixels, so the region has to turn with them.

---

## 5. TDD flow

`coding-standards.md` §4 — red, green, refactor, and the failure message gets
read. **Every row of §7 below is a test in this slice**, which is the one thing
the F1 review asked F2 to change.

| # | Red — write this test first | The failure you should read | Green |
|---|---|---|---|
| 1 | `a_form_pdf_lists_every_widget` — 63 / 89 / 105 over the three forms | `cannot find 'formFields' in scope` | `Tools/Form.swift`, annotations filtered to `Widget` |
| 2 | `the_epa_label_has_no_widgets_so_it_is_document_mode` — 0 across 45 pages | — | falls out of #1 |
| 3 | `a_read_form_document_reports_its_fields` — `Document.isForm`, 89 fields | `value of type 'Document' has no member 'isForm'` | `Document.fields`, read before rasterising |
| 4 | `a_widget_rect_lands_in_the_same_origin_as_a_line` — hand-computed at all four rotations | `got Region(0.1, 0.75, …), want Region(0.1, 0.2, …)` if the flip is missing | `region(of:in:rotation:)`. **I12** |
| 5 | `the_first_widget_of_a_real_form_is_near_the_top_of_the_page` — IRS-4835 page 1, `y < 0.5` | `first widget sits at y 0.93 — the page is upside down` | the same flip, against a real file. #4 alone can pass while self-consistently wrong |
| 6 | `checkbox_groups_keep_every_member` — 89 widgets over 84 fields | `89 widgets over 89 fields` — the assumption that a radio pair shares a `fieldName` is wrong; PDFKit puts the index in it | list per widget, and assert on the name with the trailing index stripped |
| 7 | `an_offpage_or_zero_sized_widget_is_listed_but_not_drawn` | — | `Field.isDrawable` |
| 8 | `the_step_log_never_contains_a_field_name` | — | log counts only. §5.2 |

**Checked by review, not by a test:** the four layer greps in
`scripts/layers.sh` (which already covers PDFKit), and the highlight landing on
the box — a rendering property that needs an eye on it, recorded in §7.

---

## 6. Acceptance criteria

- [x] IRS-4835 → 63 fields, Schedule F → 89, CPA-1200 → 105 — **tested**, `a_form_pdf_lists_every_widget`
- [x] EPA label → 0 widgets → document mode, decided by the file not a guess — **tested**, `the_epa_label_has_no_widgets_so_it_is_document_mode`
- [x] `acroform` fields render without a confidence ring (**I3** doesn't apply) — no ring exists in `fieldsBlock`
- [x] Clicking a field jumps to its page and highlights its rect — `ReaderModel.select(_:)` + the overlay
- [x] The mode is visible on screen, not only in the data
- [x] No field name reaches a log — **tested**, `the_step_log_never_contains_a_field_name`
- [x] `sh scripts/layers.sh` clean; PDFKit stays in `Tools`

---

## 7. Stress test

| Case | Must happen |
|---|---|
| **Highlight lands on the box** | PDFKit's rects are a *different* coordinate space from Vision's. A mirrored highlight is a second I12 bug hiding behind the first being fixed. **Tested** — `a_widget_rect_lands_in_the_same_origin_as_a_line` (4 rotations, hand-computed) and `the_first_widget_of_a_real_form_is_near_the_top_of_the_page`. The overlay itself is checked by eye. |
| Checkbox and radio groups | No duplicated names, no dropped members. **Tested** — `checkbox_groups_keep_every_member`: 89 widgets over 84 fields, and the count is per widget. |
| CPA-1200's 105 fields | List scrolls without a stall. `LazyVStack`, for the reason F1's transcript freeze established. Checked by eye. |
| A widget on a page with no text at all | Field listed. Nothing to resolve until 2.2, and nothing to crash on. |
| A widget whose rect is off-page or zero-sized | Listed, not drawn. **Tested** — `an_offpage_or_zero_sized_widget_is_listed_but_not_drawn`. |
| A page with a zero-sized mediaBox | Skipped rather than dividing by zero into a NaN region. The damaged-page fixture reaches this. |

---

## 8. Design elements this slice does not build

| # | The design proposes | `context/` says | 2.1 |
|---|---|---|---|
| 1 | A `PDFView` with native annotation rendering | Nothing requires it; F1 already renders a raster | Overlay on the existing raster. A `PDFView` in layer 4 would also be the tempting way to break the PDFKit grep |
| 2 | Fields as entries in the findings list | `Finding` is slice 3.1's contract, and its `quote` cannot describe a widget | Separate `Field` type; F3 may bridge them if it needs one stream |

---

## 9. Out of scope for 2.1

Slice **2.2** — human labels for cryptic IRS field names, nearest printed text,
left then above. Deferred deliberately: `issues.md`'s own cut order puts 2.2
third, NRCS names are already readable, and the demo beat works with raw names.

**Carried decision for when 2.2 lands:** its accuracy is measured as the OCR
confidence of the line each label was taken from, aggregated over the resolved
fields — *not* the FUNSD harness `issues.md` originally named. FUNSD pages carry
no AcroForm widgets, so scoring against them needs a rig that fabricates
pseudo-widgets from FUNSD's annotation boxes, which is a slice of its own. The
field stays exact; only the label is inferred, so only the label carries a number.

Also out of scope: findings and validators (F3), summaries (F4), any egress (F5),
and filling, saving or submitting a field — forbidden outright by **I8** and
`project-overview.md` §8.
