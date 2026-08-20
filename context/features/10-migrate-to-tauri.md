# F10 · Tauri shell

**The user can** — not yet anything. This slice renders a window on all three
desktop platforms and holds nothing behind it.

Epic · [#25](https://github.com/adisagar2003/PigeonEye/issues/25) ·
Stack, boundaries, invariants · `../architecture.md` §6, §8, §9.1, §11 ·
Status · `../progress-tracker.md` ·
How code gets written · `../coding-standards.md` ·
Agent rules · `../../ai-workflow.md`

**Precedence.** Where this file and `context/` disagree, `context/` wins.

---

## 1. Demo

```sh
cd app/src-tauri && cargo run
```

A window titled **PigeonEye** opens, 1100×760, dark. It says which slice it is
and what is not behind it yet. That is the whole demo, and the honesty is the
point: a shell that looks finished invites review of a product that does not
exist yet.

Verified on macOS 26, `rustc 1.98.0`: builds in 1m10s cold, and System Events
reports the window as `PigeonEye, 1100, 760`.

No `npm install`. No dev server. No Tauri CLI. `frontendDist` points at a
directory of two static files, so `cargo run` is the entire toolchain.

---

## 2. Settled before writing this

| Question | Answer | Whose |
|---|---|---|
| Does the Rust PDF story hold at all? | **Yes** — `pdfium-render` gives typed form fields, `PdfPageAnnotationCommon::bounds()` for the rect, page index from iterating pages, and rasterise-with-clipping. See #25's Phase 1 comment | measured |
| Pure Rust, or Pdfium? | **Pdfium.** The `lopdf`-based crates do not document widget rects, and no rect means no `crop_region()` and no bbox to anchor a quote to. Every confidence reading in this product hangs off bboxes | measured |
| What happens to "0 dependencies"? | **It stops being true**, and it gets replaced or dropped deliberately rather than discovered at release. Tauri already ships a webview; Pdfium is one more native binary | yours to call |
| Frontend framework | **None in this slice.** Two static files. Picking React/Svelte before there is a single command to call is a decision made with no information | mine, reversible |
| Where does the Tauri app live? | `app/`, beside `Package.swift`. The Swift app stays shippable until parity — two roots, one repo, no branch juggling | mine |
| Does this slice touch layers 0–4? | **No.** Not one line of `Sources/` moves. The layer rules in `coding-standards.md` §1 are untouched because there is nothing yet to violate them | already settled |
| Is portable OCR viable at all? | **Already measured — Tesseract is within 1 point of Apple Vision on CER** (27.8% vs 26.9%), `progress-tracker.md` "OCR engines — three-way benchmark". The cross-platform tool layer was never a leap of faith | already settled |
| Rust toolchain | Installed via `rustup`, minimal profile, `--no-modify-path`. Nothing was added to the shell profile; `cargo` is at `~/.cargo/bin` | mine |

Pinned deliberately, not left floating: `tauri 2.11`, `tauri-build 2.6`.

---

## 3. What is real in this slice, and what is empty

**Real.** A window that opens, sizes, has a minimum size, and carries the
product name. A `capabilities/default.json` granting `core:default` and nothing
else. A CSP of `default-src 'self'` — which is why the stylesheet is a separate
file rather than an inline `<style>` block, and the first thing to remember when
someone's inline script silently does nothing.

**Empty.** Every command. There is no `#[tauri::command]` in the tree, so the
webview can ask the Rust side for nothing at all. No plugins. No PDF crate yet —
`pdfium-render` is slice 10.2, once there is a golden-file diff to hold it to.

**One icon, because the build demands it.** The first attempt shipped no icons on
the theory that packaging is Phase 6 and `cargo run` would not care. It does:
`tauri::generate_context!` reads `icons/icon.png` **at compile time** and the
build fails without it. So `icons/icon.svg` is committed with a `sips`-rendered
`icon.png` beside it. It is a placeholder drawn from the README badge palette,
not a designed mark. The rest of the bundle set — `32x32.png`, `128x128.png`,
`icon.icns`, `icon.ico` — is still absent, so packaging still cannot happen, and
that part *is* Phase 6.

**Still empty and worth saying out loud.** There is no consent gate here, and
there is also nothing to consent to — no socket exists in the Rust tree. The
moment one does, it lives in exactly one file and `scripts/layers.sh` grows a
Rust arm. The no-network claim in this build is the absence of an API, which is
where the Swift build's claim started too.

---

## 4. Acceptance criteria

- [x] `cargo run` in `app/src-tauri` opens a window on macOS
- [x] The window is titled PigeonEye and opens at 1100×760
- [x] `rg '#\[tauri::command\]' app` is empty — this slice exposes no commands
- [x] `rg 'reqwest|ureq|hyper|TcpStream' app/src-tauri/src` is empty
- [x] Both of the above are now the sixth check in `scripts/layers.sh`, so they are enforced rather than asserted here
- [x] `Sources/` is untouched — `git diff --stat HEAD -- Sources` is empty
- [ ] Windows and Linux — **unverified, no machine to hand.** The claim in this slice's title is macOS only until CI exists (Phase 6)
- [ ] The Swift app still builds and its 73 tests still pass — not re-run, on the grounds that `Sources/` and `Package.swift` are untouched. Worth one `swift test` before merge anyway

The last two are the ones that matter. This commit is only safe because it
cannot have broken anything.

---

## 5. Stress test

| Case | Must happen |
|---|---|
| Reviewer opens the window expecting the product | The window says which slice it is and what is missing. A polished placeholder gets reviewed as a product and wastes the review. |
| Someone adds an inline `<style>` or `<script>` | It is blocked by `default-src 'self'` and fails silently. Documented here rather than rediscovered at 1am. |
| Someone runs `cargo tauri build` | It fails on the missing bundle icon set. Correct — packaging is Phase 6 and a half-signed bundle is worse than none. |
| Someone deletes `icons/icon.png` as unused | The build stops compiling. It is read by `generate_context!`, not by the bundler, so it is load-bearing at a point nobody expects. |
| The Pdfium diff comes back with divergences | Slice 10.2 stops and the divergences get adjudicated per file. PDFKit is the incumbent, not automatically the correct answer. |
| OCR evaluation comes back materially worse than Vision | The epic stops at Phase 1, per #25. This slice is deliberately cheap so that stopping costs almost nothing. |
| Someone reads the benchmark as "Tesseract is fine" | It is fine *on CER*. It is clearly worse on **BER — 31.6% vs 20.1%** — which means it mangles more whole words, and a mangled word is what a quote is made of. That is the number Phase 1 has to hold, not CER. |
| `app/src-tauri/target` gets committed | `.gitignore` in `app/src-tauri` covers `target` and `gen/schemas`. |

---

## 6. Deferred, with the reason

| Deferred | Until | Why not now |
|---|---|---|
| Frontend framework choice | there is a command to call | No information to choose on yet |
| `pdfium-render` wiring | slice 10.2 | Wants the golden-file diff in the same change, or the port is unverified |
| OCR backend | Phase 1 exit | Tesseract is the working assumption; the open question is BER, not viability. Untested and worth a look first: RapidOCR with an *English* recogniser, and PaddleOCR PP-Structure for the reading-order weakness — both already named in `progress-tracker.md` |
| A designed icon, signing, notarisation, auto-update | Phase 6 | Nothing to ship yet; the committed icon is a placeholder that only exists to let the build link |
| Billing | Phase 5 | Explicitly after parity, behind a flag |
