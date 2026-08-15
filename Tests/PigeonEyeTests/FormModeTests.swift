import CoreGraphics
import Foundation
import Testing

@testable import Agent
@testable import Contracts
@testable import Tools

// The TDD flow in context/features/02-form-mode.md §5, in order.
//
// Every row of that spec's §7 stress table is a test here rather than prose to
// check by hand. That is the F1 review's lesson: all four F1 defects were cases
// §7 already listed and no test covered.

/// `Region` arithmetic is floating point; comparing the four components exactly
/// would flap on the last bit without saying anything about the geometry.
private func expectRegion(
    _ got: Region, _ want: Region,
    _ what: String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let tolerance = 1e-9
    let close =
        abs(got.x - want.x) < tolerance && abs(got.y - want.y) < tolerance
        && abs(got.width - want.width) < tolerance && abs(got.height - want.height) < tolerance
    #expect(close, "\(what): got \(got), want \(want)", sourceLocation: sourceLocation)
}

// MARK: - 1 · The field list comes from the file

/// The counts are `spike_form.swift`'s, reproduced. They are exact rather than a
/// floor on purpose: this is the one number in the product that is ground truth
/// read out of the file, so a drift in it is a defect, not a measurement.
@Test(arguments: [
    ("IRS-4835", Fixture.irs4835, 63),
    ("Schedule F", Fixture.form, 89),
    ("CPA-1200", Fixture.cpa1200, 105),
])
func a_form_pdf_lists_every_widget(name: String, url: URL, expected: Int) throws {
    let fields = try formFields(pdf: url)
    #expect(fields.count == expected, "\(name) listed \(fields.count) fields, expected \(expected)")
    #expect(fields.allSatisfy { $0.page >= 1 }, "\(name) has a field with a 0-based or missing page")
}

// MARK: - 2 · The mode is decided by the file, not by a guess

/// 45 pages of EPA labelling and not one fillable field. This is the negative
/// half of the mode test, and it is what makes the test deterministic instead of
/// a threshold someone has to defend.
@Test func the_epa_label_has_no_widgets_so_it_is_document_mode() throws {
    #expect(try formFields(pdf: Fixture.label).isEmpty)
}

/// The Agent wiring, not just the tool: a read Document knows it is a form.
@Test func a_read_form_document_reports_its_fields() async throws {
    let doc = try await read(Fixture.form)
    #expect(doc.isForm)
    #expect(doc.fields.count == 89)
    #expect(doc.fields.allSatisfy { $0.page <= doc.pageCount })
}

// MARK: - 3 · One coordinate origin, still (I12)

/// **The stress case that matters.** `PDFAnnotation.bounds` is PDF user space —
/// lower-left, unnormalised, offset by the mediaBox origin. `Region` is
/// normalised upper-left, the space `Tools.ocr` already converts to. Getting this
/// backwards mirrors every highlight vertically, which survives eyeballing on a
/// symmetric form and is a second I12 bug hiding behind the first one being
/// fixed.
///
/// Hand-computed against a 600 × 800 box and a rect 60pt from the left whose top
/// edge sits 640pt up, so the answer is 0.1 across and 0.2 down at rotation 0.
@Test(arguments: [
    (0, Region(x: 0.1, y: 0.2, width: 0.2, height: 0.05)),
    (90, Region(x: 0.75, y: 0.1, width: 0.05, height: 0.2)),
    (180, Region(x: 0.7, y: 0.75, width: 0.2, height: 0.05)),
    (270, Region(x: 0.2, y: 0.7, width: 0.05, height: 0.2)),
])
func a_widget_rect_lands_in_the_same_origin_as_a_line(rotation: Int, want: Region) {
    let box = CGRect(x: 0, y: 0, width: 600, height: 800)
    let rect = CGRect(x: 60, y: 600, width: 120, height: 40)
    expectRegion(region(of: rect, in: box, rotation: rotation), want, "rotation \(rotation)")
}

/// A mediaBox whose origin is not zero — the offset is subtracted, not ignored.
@Test func a_widget_rect_is_measured_from_the_mediabox_origin() {
    let box = CGRect(x: 100, y: 50, width: 600, height: 800)
    let rect = CGRect(x: 160, y: 650, width: 120, height: 40)
    expectRegion(
        region(of: rect, in: box, rotation: 0),
        Region(x: 0.1, y: 0.2, width: 0.2, height: 0.05),
        "mediaBox origin ignored")
}

/// The real fixture, because the pure function can be self-consistently wrong.
/// IRS-4835's first widget is the name box in the top third of page 1; if the
/// flip is missing it reads as 0.9-something instead.
@Test func the_first_widget_of_a_real_form_is_near_the_top_of_the_page() throws {
    let first = try #require(try formFields(pdf: Fixture.irs4835).first { $0.page == 1 })
    #expect(first.region.y < 0.5, "first widget sits at y \(first.region.y) — the page is upside down")
}

// MARK: - 4 · Checkbox and radio groups

/// Checkbox and radio members are separate widgets of one field, distinguished
/// only by the trailing index PDFKit puts in `fieldName` — `c1_2[0]` and
/// `c1_2[1]` are the two boxes of one yes/no. Schedule F has **89 widgets across
/// 84 fields**: five pairs. Listing per field instead of per widget would drop
/// one box of every pair, and the loss would be invisible on screen.
@Test func checkbox_groups_keep_every_member() throws {
    let fields = try formFields(pdf: Fixture.form)
    #expect(fields.count == 89)

    let byField = Set(
        fields.map {
            $0.name.replacingOccurrences(of: "\\[[0-9]+\\]$", with: "", options: .regularExpression)
        })
    #expect(
        byField.count == 84,
        "\(fields.count) widgets over \(byField.count) fields — the checkbox pairs have been collapsed")
}

// MARK: - 5 · Degenerate rects are listed, not drawn

/// A widget with a zero-sized or off-page rect still belongs in the list — it is
/// a field the user must fill. It just has nothing to highlight, and a region of
/// zero size must not be clamped into one that covers the page.
@Test func an_offpage_or_zero_sized_widget_is_listed_but_not_drawn() {
    func field(_ region: Region) -> Field {
        Field(name: "x", kind: "/Tx", page: 1, region: region)
    }
    let box = CGRect(x: 0, y: 0, width: 600, height: 800)
    let empty = region(of: CGRect(x: 60, y: 600, width: 0, height: 0), in: box, rotation: 0)

    #expect(!field(empty).isDrawable, "a zero-sized rect")
    // Off-page is the half a size check misses: these all have positive width
    // and height, and all point at nothing.
    #expect(!field(Region(x: 1.1, y: 0.2, width: 0.1, height: 0.1)).isDrawable, "wholly right of the page")
    #expect(!field(Region(x: -0.5, y: 0.2, width: 0.3, height: 0.1)).isDrawable, "wholly left of the page")
    #expect(!field(Region(x: 0.2, y: 1.4, width: 0.1, height: 0.1)).isDrawable, "wholly below the page")
    #expect(!field(Region(x: .nan, y: 0.2, width: 0.1, height: 0.1)).isDrawable, "a NaN rect")

    #expect(field(Region(x: 0.1, y: 0.2, width: 0.2, height: 0.05)).isDrawable)
    // Straddling an edge still draws — it is partly on the page.
    #expect(field(Region(x: -0.05, y: 0.2, width: 0.2, height: 0.05)).isDrawable)
}

/// A form's field list is read from the whole file, but OCR stops at
/// `Limits.maxPages`. Listing a field the reader then refuses to navigate to
/// would be the app lying about its own list — so the navigable range covers
/// every page it shows something for. Rasterising needs no OCR, so there is
/// nothing to stop it.
@Test func a_field_past_the_ocr_page_cap_is_still_navigable() {
    let far = Field(name: "late", kind: "/Tx", page: 150,
                    region: Region(x: 0.1, y: 0.1, width: 0.2, height: 0.02))
    let doc = Document(
        url: Fixture.form, kind: .pdf, pageCount: 200, pagesRead: Limits.maxPages,
        capped: true, pages: [], failedPages: [], fields: [far], findings: [], log: [])

    #expect(doc.navigablePageCount == 150, "a field on page 150 is not reachable")

    let plain = Document(
        url: Fixture.label, kind: .pdf, pageCount: 200, pagesRead: Limits.maxPages,
        capped: true, pages: [], failedPages: [], fields: [], findings: [], log: [])
    #expect(plain.navigablePageCount == Limits.maxPages, "a document with no fields grew its page range")
}

/// Measured, not assumed: **PDFKit drops annotations on a zero-sized page.** The
/// identical widget dictionary reads as one `Widget` on a 612×792 page and as
/// nothing at all on a 0×0 one, so a malformed page's field never reaches our
/// media-box guard — the framework ate it first.
///
/// The guard stays because dividing by a zero box is still how you get a NaN
/// region, and this test is what stops someone "fixing" a branch that cannot
/// run.
@Test func pdfkit_hides_widgets_on_a_zero_sized_page() throws {
    let fields = try formFields(pdf: Fixture.zeroSizedPage)
    #expect(fields.isEmpty, "PDFKit started reporting these — the guard now needs to list them")
}

// MARK: - 6 · A field name is document content

/// `topmostSubform[0].Page1[0].f1_04[0]` and `Applicant Decision Maker` are both
/// text out of the user's document, and `coding-standards.md` §5.2 allowlists the
/// log to counts. The F1 test covers the transcript and the filename; this covers
/// the thing F2 adds.
@Test func the_step_log_never_contains_a_field_name() async throws {
    let doc = try await read(Fixture.form)
    let names = Set(doc.fields.map(\.name))

    for entry in doc.log {
        #expect(!entry.message.contains("topmostSubform"), "log entry leaks a field name: \(entry.message)")
        for name in names {
            #expect(!entry.message.contains(name), "log entry leaks a field name: \(entry.message)")
        }
    }
}
