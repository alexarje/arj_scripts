#!/usr/bin/env python3
"""Generate a PDF folder inventory report with pie charts."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile
from pathlib import Path

def count_files_by_type(folder: Path, extensions: list[str]) -> int:
    count = 0
    for root, _, files in os.walk(folder):
        for file in files:
            if any(file.lower().endswith(ext) for ext in extensions):
                count += 1
    return count


def total_size_by_type(folder: Path, extensions: list[str]) -> int:
    total_size = 0
    for root, _, files in os.walk(folder):
        for file in files:
            if any(file.lower().endswith(ext) for ext in extensions):
                total_size += os.path.getsize(os.path.join(root, file))
    return total_size


def file_owners_by_type(folder: Path, extensions: list[str]) -> dict[str, int]:
    owners: dict[str, int] = {}
    for root, _, files in os.walk(folder):
        for file in files:
            if any(file.lower().endswith(ext) for ext in extensions):
                owner = (
                    subprocess.check_output(["ls", "-ld", os.path.join(root, file)])
                    .split()[2]
                    .decode("utf-8")
                )
                owners[owner] = owners.get(owner, 0) + 1
    return owners


def format_size(size: float) -> str:
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if size < 1024:
            return f"{size:.2f} {unit}"
        size /= 1024
    return f"{size:.2f} PB"


def create_pie_chart(data: dict[str, int], title: str, filename: Path) -> None:
    import matplotlib.pyplot as plt

    plt.figure(figsize=(10, 6))
    plt.pie(data.values(), labels=data.keys(), autopct="%1.1f%%", startangle=140)
    plt.axis("equal")
    plt.title(title)
    plt.savefig(filename)
    plt.close()


def create_pdf_report(report_data: dict, output_pdf: Path, counts_chart: Path, sizes_chart: Path) -> None:
    from fpdf import FPDF

    pdf = FPDF()
    pdf.add_page()
    pdf.set_font("Arial", size=12)

    pdf.cell(200, 10, txt="Folder Report", ln=True, align="C")
    pdf.cell(200, 10, txt="Number of files by type:", ln=True)
    for file_type, count in report_data["file_counts"].items():
        pdf.cell(200, 10, txt=f"{file_type}: {count}", ln=True)

    pdf.cell(200, 10, txt="Total size by type:", ln=True)
    for file_type, size in report_data["total_sizes"].items():
        pdf.cell(200, 10, txt=f"{file_type}: {format_size(size)}", ln=True)

    pdf.cell(200, 10, txt="File owners by type:", ln=True)
    for file_type, owners in report_data["file_owners"].items():
        pdf.cell(200, 10, txt=f"{file_type}:", ln=True)
        for owner, count in owners.items():
            pdf.cell(200, 10, txt=f"  {owner}: {count}", ln=True)

    pdf.add_page()
    pdf.image(str(counts_chart), x=10, y=20, w=180)
    pdf.add_page()
    pdf.image(str(sizes_chart), x=10, y=20, w=180)
    pdf.output(str(output_pdf))


def main(folder: Path, output_pdf: Path) -> None:
    file_types = {
        "Audio": [".mp3", ".wav", ".flac"],
        "Video": [".mp4", ".avi", ".mkv"],
        "Documents": [".pdf", ".docx", ".xlsx"],
        "Images": [".jpg", ".png", ".gif"],
    }

    report_data = {
        "file_counts": {},
        "total_sizes": {},
        "file_owners": {},
    }

    for file_type, extensions in file_types.items():
        report_data["file_counts"][file_type] = count_files_by_type(folder, extensions)
        report_data["total_sizes"][file_type] = total_size_by_type(folder, extensions)
        report_data["file_owners"][file_type] = file_owners_by_type(folder, extensions)

    with tempfile.TemporaryDirectory() as tmpdir:
        tmp = Path(tmpdir)
        counts_chart = tmp / "file_counts_pie_chart.png"
        sizes_chart = tmp / "total_sizes_pie_chart.png"
        create_pie_chart(report_data["file_counts"], "Number of Files by Type", counts_chart)
        create_pie_chart(report_data["total_sizes"], "Total Size by Type", sizes_chart)
        create_pdf_report(report_data, output_pdf, counts_chart, sizes_chart)

    print(f"Wrote {output_pdf}")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="PDF folder inventory report with pie charts.")
    parser.add_argument(
        "folder",
        nargs="?",
        type=Path,
        default=Path("."),
        help="Directory to scan (default: current directory)",
    )
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=Path("folder_report.pdf"),
        help="Output PDF path (default: folder_report.pdf)",
    )
    return parser.parse_args(argv)


if __name__ == "__main__":
    args = parse_args()
    folder = args.folder.expanduser().resolve()
    if not folder.is_dir():
        print(f"Error: directory not found: {folder}", file=sys.stderr)
        raise SystemExit(1)
    main(folder, args.output.expanduser().resolve())
