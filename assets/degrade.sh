#!/bin/sh
# Government PDFs are born-digital, so pdftotext reads them perfectly and never
# exercises the OCR path. Render them to lossy images first: that IS the test input.
#   ./degrade.sh [dpi] [quality]   e.g. ./degrade.sh 72 25  for a bad tractor-cab photo
set -e
cd "$(dirname "$0")"
dpi=${1:-100}; q=${2:-40}
rm -rf scans; mkdir -p scans
for f in epa-labels/*.pdf gov-forms/*.pdf; do
  pdftoppm -jpeg -r "$dpi" -jpegopt quality="$q" -f 1 -l 2 "$f" "scans/$(basename "$f" .pdf)"
done
echo "$(ls scans | wc -l | tr -d ' ') images at ${dpi}dpi q${q} -> assets/scans/"
