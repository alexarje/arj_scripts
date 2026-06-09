#!/usr/bin/env python3
"""Rank PDFs in a directory by extracted word count."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

def count_words_in_pdf(file_path: Path) -> int:
    import PyPDF2

    try:
        with file_path.open("rb") as file:
            reader = PyPDF2.PdfReader(file)
            text = "".join(page.extract_text() or "" for page in reader.pages)
            return len(text.split())
    except Exception as exc:
        print(f"Error reading {file_path}: {exc}", file=sys.stderr)
        return 0


def rank_pdfs_by_word_count(directory: Path) -> None:
    pdf_files = sorted(directory.glob("*.pdf"))
    if not pdf_files:
        print(f"No PDF files found in {directory}", file=sys.stderr)
        raise SystemExit(1)

    ranked = sorted(
        ((pdf.name, count_words_in_pdf(pdf)) for pdf in pdf_files),
        key=lambda item: item[1],
        reverse=True,
    )
    for pdf, count in ranked:
        print(f"{pdf}: {count} words")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Rank PDFs in a folder by word count.")
    parser.add_argument(
        "directory",
        nargs="?",
        type=Path,
        default=Path("."),
        help="Directory containing PDF files (default: current directory)",
    )
    return parser.parse_args(argv)


if __name__ == "__main__":
    args = parse_args()
    directory = args.directory.expanduser().resolve()
    if not directory.is_dir():
        print(f"Error: directory not found: {directory}", file=sys.stderr)
        raise SystemExit(1)
    rank_pdfs_by_word_count(directory)
