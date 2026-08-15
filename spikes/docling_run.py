#!/usr/bin/env python3
"""Run docling over one page and print what it read.

Spike for the "docling instead of OCR" question. Dies when the tracker records
an answer.

Two configurations, because they answer two different questions and conflating
them is how this decision gets made wrongly:

    --mode text   docling's default: the PDF's own text layer, plus the layout
                  and TableFormer models for structure. Answers "does docling
                  recover page 34's rate table?"
    --mode ocr    `force_full_page_ocr`: throws the text layer away and reads
                  the pixels. Answers "is docling's OCR better than Vision's?",
                  which is the only comparison where Vision's 1/186 is the
                  fair baseline.

`--tables` prints the table as cells rather than as prose, because a rate table
flattened into a line of markdown has already lost the row/column pairing that
makes a rate mean something.

    python spikes/docling_run.py <pdf> 34 --mode text
"""

import argparse
import sys
import time


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("pdf")
    ap.add_argument("page", type=int)
    ap.add_argument("--mode", choices=["text", "ocr"], default="text")
    ap.add_argument("--tables", action="store_true", help="print table cells too")
    args = ap.parse_args()

    from docling.datamodel.base_models import InputFormat
    from docling.datamodel.pipeline_options import PdfPipelineOptions
    from docling.document_converter import DocumentConverter, PdfFormatOption

    opts = PdfPipelineOptions()
    opts.do_table_structure = True
    opts.table_structure_options.do_cell_matching = True
    if args.mode == "ocr":
        opts.do_ocr = True
        opts.ocr_options.force_full_page_ocr = True
    else:
        # Structure still comes from the models; the *text* comes from the file.
        opts.do_ocr = False

    converter = DocumentConverter(
        format_options={InputFormat.PDF: PdfFormatOption(pipeline_options=opts)})

    start = time.monotonic()
    # An image input is the only way to prove OCR actually ran: with a PDF,
    # `force_full_page_ocr` still let the text layer win — the two modes came
    # back byte-identical. A JPEG has no text layer to fall back to.
    if args.pdf.lower().endswith((".jpg", ".jpeg", ".png")):
        result = converter.convert(args.pdf)
    else:
        result = converter.convert(args.pdf, page_range=(args.page, args.page))
    elapsed = time.monotonic() - start
    doc = result.document

    print(doc.export_to_markdown())

    if args.tables:
        print(f"\n--- {len(doc.tables)} table(s) ---", file=sys.stderr)
        for i, table in enumerate(doc.tables):
            frame = table.export_to_dataframe()
            print(f"table {i}: {frame.shape[0]} rows × {frame.shape[1]} cols",
                  file=sys.stderr)
            print(frame.to_string(max_rows=8), file=sys.stderr)

    print(f"\n[{args.mode}] {elapsed:.1f}s, {len(doc.tables)} tables",
          file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
