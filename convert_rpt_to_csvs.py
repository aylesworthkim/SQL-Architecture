"""
Convert an SSMS "Results to File" .rpt containing multiple query results
into one CSV per query.

The .rpt format is fixed-width text:
    column1   column2     column3
    -------   ---------   ---------
    val1      val2        val3
    ...
    (N rows affected)
    column1'  column2'    ...        ← next query begins

Strategy:
  - Stream the file line-by-line (it can be multi-GB).
  - The dashes line ("---- ---- ----") tells us column boundaries.
  - The line BEFORE it is the column header.
  - Data rows follow until another dashes line or "(N rows affected)".
  - The first data row in each section is the SP's synthetic sort=1 header
    row (text labels), which we skip.
  - The "sort" column itself is dropped from CSV output — it's an internal
    ordering artifact, not real data.

Usage:
    python convert_rpt_to_csvs.py <input.rpt> [output_dir]

Output:
    section1.csv, section2.csv, section3.csv, section4.csv
    (You'll rename to Customers/Sales/Stores/Transactions after based on
     the column fingerprints printed during processing.)
"""

import csv
import os
import re
import sys
import time
from typing import List, Optional, Tuple, TextIO

# Match a line that is only dashes and whitespace, with at least one dash.
DASHES_LINE = re.compile(r'^[\s-]*-[\s-]*$')

# "(123456 rows affected)" — appears at the end of each result set.
ROWS_AFFECTED = re.compile(r'^\(\s*\d+\s+rows?\s+affected\s*\)\s*$', re.IGNORECASE)


def parse_dashes(dashes_line: str) -> List[Tuple[int, int]]:
    """Given a dashes line, return list of (start, end_exclusive) col bounds."""
    bounds = []
    i = 0
    n = len(dashes_line)
    while i < n:
        while i < n and dashes_line[i] != '-':
            i += 1
        if i >= n:
            break
        start = i
        while i < n and dashes_line[i] == '-':
            i += 1
        bounds.append((start, i))
    return bounds


def slice_row(line: str, bounds: List[Tuple[int, int]]) -> List[str]:
    """Extract values from a fixed-width line at the given column boundaries."""
    out = []
    for start, end in bounds:
        # Pad short lines to handle ragged-right input.
        chunk = line[start:end] if start < len(line) else ''
        out.append(chunk.strip())
    return out


def open_section(output_dir: str, section: int, columns: List[str]) -> Tuple[TextIO, csv.writer, List[int]]:
    """Open a new CSV for a fresh section. Returns (file, writer, kept_indexes)."""
    path = os.path.join(output_dir, f'section{section}.csv')
    fh = open(path, 'w', newline='', encoding='utf-8')
    writer = csv.writer(fh, quoting=csv.QUOTE_MINIMAL)

    # Drop the synthetic "sort" column if present (it's always column 0).
    kept = [i for i, c in enumerate(columns) if c.lower() != 'sort']
    csv_header = [columns[i] for i in kept]
    writer.writerow(csv_header)

    print(f"  Section {section} → {path}")
    print(f"    Columns: {csv_header}")
    return fh, writer, kept


def main():
    if len(sys.argv) < 2:
        print("Usage: python convert_rpt_to_csvs.py <input.rpt> [output_dir]")
        sys.exit(1)

    rpt_path = sys.argv[1]
    output_dir = sys.argv[2] if len(sys.argv) > 2 else os.path.dirname(rpt_path) or '.'
    os.makedirs(output_dir, exist_ok=True)

    file_size = os.path.getsize(rpt_path)
    print(f"Input:  {rpt_path}  ({file_size / (1024 ** 3):.2f} GB)")
    print(f"Output: {output_dir}")
    print()

    section = 0
    bounds: Optional[List[Tuple[int, int]]] = None
    kept_indexes: List[int] = []
    out_fh: Optional[TextIO] = None
    out_writer: Optional[csv.writer] = None
    skipped_synthetic_header = False
    prev_line = ''
    section_row_count = 0

    bytes_seen = 0
    last_progress = time.time()
    start_time = time.time()

    # encoding='utf-8-sig' auto-strips a UTF-8 BOM if SSMS wrote one (it does
    # by default). Without this, the BOM shifts the first line by 1 character
    # and our fixed-width slicing truncates the section-1 column header.
    # errors='replace' keeps us from crashing on stray bytes.
    with open(rpt_path, 'r', encoding='utf-8-sig', errors='replace') as f:
        for line in f:
            bytes_seen += len(line)
            stripped = line.rstrip('\r\n')

            # Progress every 5s so the operator knows it's alive.
            now = time.time()
            if now - last_progress > 5:
                pct = 100.0 * bytes_seen / file_size if file_size else 0
                print(f"    [{pct:5.1f}%] section {section}, rows {section_row_count}")
                last_progress = now

            # Boundary line ("---- ---- ----")?
            if DASHES_LINE.match(stripped) and '-' in stripped:
                # Close previous section if open.
                if out_fh is not None:
                    out_fh.close()
                    print(f"    Section {section} done — {section_row_count} rows.\n")

                section += 1
                bounds = parse_dashes(stripped)
                columns = slice_row(prev_line, bounds) if prev_line else []
                out_fh, out_writer, kept_indexes = open_section(output_dir, section, columns)
                skipped_synthetic_header = False
                section_row_count = 0
                prev_line = stripped
                continue

            # "(N rows affected)" — end of a section's data, ignore.
            if ROWS_AFFECTED.match(stripped):
                prev_line = stripped
                continue

            # Blank line — ignore.
            if not stripped.strip():
                prev_line = stripped
                continue

            # Data row (or the SP's synthetic header row).
            if bounds is not None and out_writer is not None:
                values = slice_row(stripped, bounds)

                # Skip the SP's synthetic sort=1 header row — happens once per section.
                if not skipped_synthetic_header:
                    skipped_synthetic_header = True
                    if values and values[0] == '1':
                        prev_line = stripped
                        continue
                    # Otherwise it's a real data row — fall through and write it.

                kept_values = [values[i] for i in kept_indexes]
                out_writer.writerow(kept_values)
                section_row_count += 1

            prev_line = stripped

    if out_fh is not None:
        out_fh.close()
        print(f"    Section {section} done — {section_row_count} rows.\n")

    elapsed = time.time() - start_time
    print(f"All done in {elapsed:.1f}s.")
    print(f"Sections written: {section}")


if __name__ == '__main__':
    main()
