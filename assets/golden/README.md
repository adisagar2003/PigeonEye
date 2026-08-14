# Golden sets

Public, human-labelled datasets with ground truth, downloaded here to answer two
questions from `context/project-overview.md` that `assets/scans/` cannot answer
on its own:

- **§12.4 — what confidence thresholds?** Currently to be picked against 18 scans
  that were degraded by `degrade.sh`, i.e. one synthetic noise distribution. A
  threshold tuned on synthetic noise is a threshold tuned on `degrade.sh`.
- **§7.1 — is the confidence signal calibrated?** Needs many labelled items with
  known-correct answers. 18 pages is not enough to bin a reliability curve.

Everything here is **generalisation cover**, not a domain benchmark. None of it
is an EPA label. `eval/cases.json` stays the domain ground truth; these tell you
whether the pipeline works on documents it was not tuned on.

Fetch or refresh everything: `./assets/golden/fetch.sh`

---

## The map

| Set | Scores which stage | Catches what `assets/scans/` can't |
|---|---|---|
| `funsd/` | §5 step 2 (OCR), §11a.1 (label resolution) | Real scanner/fax noise instead of `degrade.sh` noise |
| `kleister-charity/` | §5 step 3a (deterministic extraction + validators) | Long documents, typed fields, and **decoy keys** — hallucination bait at scale |
| `govreport/` | §5 step 3b (explanation) | Whether summaries of government prose are faithful, judged against expert-written ones |
| `cuad/` | Obligations & deadlines (§1, §6.1 urgency) | Obligation spans labelled by lawyers — the one thing your product claims and nothing else here labels |
| `nist-sfrs/` | §11a form mode, incl. **Schedule F** | Per-field ground truth on real IRS forms. **Not fetched** — opt in with `./fetch.sh nist`, see caveats |

---

## FUNSD — 199 noisy scanned forms

`funsd/dataset/{training_data,testing_data}/{images,annotations}` — 149 train, 50 test.

Each annotation JSON is a list of entities:

```json
{"box": [102, 406, 147, 423], "text": "DATE:", "label": "question",
 "words": [{"box": [...], "text": "DATE:"}], "linking": [[2, 27]], "id": 2}
```

Three separate things you can score with it:

1. **OCR fidelity** — `text` per entity is the ground-truth transcription, with a
   bbox. Feed the image to `./ocr`, match by bbox overlap, score with
   `eval/ocr_bench.py`'s `cer()` / `wer()` / `ber()`. Note those three functions
   are reusable as-is, but the corpus is not: `pairs()` globs `assets/scans/`
   and `truth_for()` shells out to `pdftotext`. Running FUNSD through it needs a
   second truth source — read `text` out of the annotation JSON — not new
   metrics. Not wired up; that is a §11 layer-1 job.
2. **Label resolution (§11a.1)** — `linking` pairs a `question` entity to its
   `answer` entity. That is *exactly* the unsolved problem in §11a.1: given a
   field's rect, find the printed label that belongs to it. This is 50 test forms
   of ground truth for a geometry heuristic you were about to write blind.
3. **Confidence calibration** — every entity is either read correctly or not, so
   Vision's per-line `confidence` can be binned against real correctness. This is
   the input §12.4 is missing.

Note: some entities have `"text": ""` (figures, marks). Filter them or they
inflate CER.

**Caveat that matters for you:** FUNSD images are 1990s tobacco-litigation
documents — faxes and photocopies. The noise is real but it is *older* noise than
a modern phone scan. Treat a threshold derived here as a floor, not a target.

License: **non-commercial, research and educational use only** (EPFL-LTS5).
Fine for a hackathon; check before anything ships commercially.

## Kleister Charity — 200 long documents, typed fields, decoy keys

`kleister-charity/kleister-charity-dev-200.jsonl` — normalised from the original
TSVs. One object per document:

```json
{"id": "1ada336f...", 
 "keys_requested": ["charity_name", "charity_number", "income_annually_in_british_pounds", ...],
 "decoy_keys": ["spending_annually_in_british_pounds"],
 "expected": {"charity_number": "1155074", "address__postcode": "WR12 7NL", ...},
 "text_clean": "...",   
 "text_ocr": "..."}
```

Why this one is the closest analogue to your product:

- **Fields are typed and validator-shaped.** A charity number (`\d{6,7}`), a
  postcode, two money amounts, a date. Same shape as your Tier-2 `Finding` with
  `validated: bool`. §11 layer 2 gets a real test set instead of hand-written
  strings.
- **Decoy keys.** 97 of them across the full set. A key is requested and *no
  value exists in the document* — emitting one is a hallucination, scored as
  such. This is your `epa-524-529` "invented obligation" trap generalised to 200
  documents. Your §5.1 claim is that deterministic extraction *cannot* fabricate;
  this is where you prove it rather than assert it.
- **`text_clean` vs `text_ocr` on the same document.** Born-digital extraction
  vs Tesseract on the same pages, same labels. Run extraction over both: the
  accuracy gap is the damage OCR does, isolated from every other variable. That
  is the honest way to set the §5 step 4 escalation threshold — escalate where
  the gap opens, not where a number feels low.
- Documents are long (mean ~22 pages), which is §13 open question 5 — the
  45-page EPA label vs a 2-page window.

`dev-0.expected.tsv` is kept as the unmodified original for verification.

License: source documents are UK Charity Commission public filings; dataset
released for research by Applica.ai. Original repo: `applicaai/kleister-charity`.

## GovReport — 200 government reports with expert summaries

`govreport/govreport-validation-200.jsonl` — `{"id", "report", "summary"}`.

US GAO and Congressional Research Service reports with summaries written by the
agencies' own analysts. Same institutional register as EPA and NRCS prose, which
is what makes it a better proxy for §5.1's tier 3b than any news-summarisation
set.

Use it to compare the three tier-3b implementations from §12.1 (Foundation
Models / OpenAI / template fallback) on identical inputs. Score with an
LLM-as-judge for faithfulness — a claim in the summary that isn't in the report
is the failure you care about, and it is the same check as your
`quote ⊂ transcript` rule at §6.2, just for prose.

Reports are long — mean 7,686 words in this slice — so most local models will
need chunking, which is itself a useful finding before demo day.

License: US government works, public domain. Compiled by Huang et al. 2021.

## CUAD — 13k obligation spans in 510 contracts

`cuad/CUAD_v1.zip` — expert-annotated by The Atticus Project, 41 clause
categories over contracts from SEC EDGAR.

The only set here that labels **obligations with their source spans**. Your
product's headline claim is "the obligations and deadlines that actually
matter, every claim quoted from the source". CUAD's format is a span in the
document — the same shape as `Finding.quote` + `Finding.region`. Categories like
*Notice Period to Terminate Renewal*, *Expiration Date* and *Post-Termination
Services* are the deadline/obligation reasoning you are testing.

Contracts, not government documents, so this is the weakest domain match in the
folder. Its value is that nothing else labels obligations at all.

License: CC BY 4.0. Source contracts are public SEC filings.

## NIST SFRS2 (SD6) — IRS tax forms with per-field ground truth

`nist-sfrs/sd06.zip` — 5,595 binary form images across 12 IRS 1040 Package X
forms **including Schedule F**, each with a text file of the entry-field answers.

Directly your §3 secondary family, with field-level ground truth.

**Two caveats, both real:**

1. The forms are from **1988** and the images are 1-bit black and white
   hand-print. Layout and typography differ from a modern Schedule F.
2. §11a says form mode reads AcroForm widgets straight from the PDF, so
   confidence "is not applicable". These are *scans*, so they test the OCR path,
   not the path you actually use for born-digital forms. They only exercise
   `assets/scans/IRS-*.jpg`-style input.

**Not downloaded.** It was still streaming past 412 MB with no `Content-Length`
from NIST's S3 bucket when this machine was down to 8 GB free, so it is opt-in:
`./fetch.sh nist`. Do that if you want field-level ground truth on Schedule F
specifically; skip it otherwise — FUNSD covers scanned-form OCR with more modern
noise, and `assets/scans/IRS-*.jpg` already covers the modern layout.

License: NIST, US government work. No usage restriction stated; attribution
expected.

---

## What none of these cover

Being explicit, because the product's whole pitch is marking uncertainty rather
than hiding it:

- **No EPA labels.** No public labelled set of pesticide labelling documents
  exists. Application rates, restricted-entry intervals and PPE requirements —
  your primary family, §3 — are covered only by `eval/cases.json` and only for
  two letters.
- **No relative-deadline arithmetic.** The `epa-7969-242` trap ("18 months from
  the date of this letter", anchored against a decoy date) has no analogue here.
  That trap remains hand-built and remains the sharpest test in the repo.
- **No confidence labels.** None of these ship a per-item "how sure should you
  be". You derive that from correctness: bin your confidence, measure accuracy
  per bin, and the gap is your calibration error.
- **English only, US/UK only.**

## Sizes and licenses at a glance

| Set | On disk | License | Commercial use |
|---|---|---|---|
| FUNSD | 27 MB | EPFL-LTS5 research licence | **No** |
| Kleister Charity | 18 MB | Research release, UK public filings | Check |
| GovReport | 11 MB | Public domain (US gov work) | Yes |
| CUAD | 101 MB | CC BY 4.0 | Yes, with attribution |
| NIST SFRS2 | >412 MB, **not fetched** | US gov work | Yes |

157 MB on disk as fetched. If that is too much, `cuad/` is the next one to drop
(101 MB, weakest domain match after NIST) — `./fetch.sh` gets it back.
