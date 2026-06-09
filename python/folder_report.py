#!/usr/bin/env python3
"""Print file counts, sizes, and owners by media type for a folder."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
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


def main(folder: Path) -> None:
    file_types = {
        "Audio": [".mp3", ".wav", ".flac"],
        "Video": [".mp4", ".avi", ".mkv"],
        "Documents": [".pdf", ".docx", ".xlsx"],
        "Images": [".jpg", ".png", ".gif"],
    }

    print("Number of files by type:")
    for file_type, extensions in file_types.items():
        print(f"{file_type}: {count_files_by_type(folder, extensions)}")

    print("\nTotal size by type:")
    for file_type, extensions in file_types.items():
        print(f"{file_type}: {format_size(total_size_by_type(folder, extensions))}")

    print("\nFile owners by type:")
    for file_type, extensions in file_types.items():
        print(f"{file_type}:")
        for owner, count in file_owners_by_type(folder, extensions).items():
            print(f"  {owner}: {count}")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Text folder inventory report.")
    parser.add_argument(
        "folder",
        nargs="?",
        type=Path,
        default=Path("."),
        help="Directory to scan (default: current directory)",
    )
    return parser.parse_args(argv)


if __name__ == "__main__":
    args = parse_args()
    folder = args.folder.expanduser().resolve()
    if not folder.is_dir():
        print(f"Error: directory not found: {folder}", file=sys.stderr)
        raise SystemExit(1)
    main(folder)
