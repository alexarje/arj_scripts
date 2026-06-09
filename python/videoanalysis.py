#!/usr/bin/env python3
"""Run musicalgestures visualizations on videos in a directory."""

from __future__ import annotations

import argparse
import glob
import os
import sys
from pathlib import Path

def process_videos(folder: Path) -> None:
    import musicalgestures as mg
    patterns = ["*.mp4", "*.MP4", "*.avi", "*.AVI"]
    video_files: list[str] = []
    for pattern in patterns:
        video_files.extend(glob.glob(str(folder / pattern)))

    if not video_files:
        print(f"No video files found in {folder}", file=sys.stderr)
        raise SystemExit(1)

    for file_path in sorted(video_files):
        print(f"Processing {file_path}")
        video = mg.MgVideo(file_path)
        video.average()
        video.directograms()
        video.motion()
        video.audio.waveform()
        video.audio.spectrogram()
        video.audio.tempogram()


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate musicalgestures plots for videos in a directory.",
    )
    parser.add_argument(
        "folder",
        nargs="?",
        type=Path,
        default=Path("."),
        help="Directory containing video files (default: current directory)",
    )
    return parser.parse_args(argv)


if __name__ == "__main__":
    args = parse_args()
    folder = args.folder.expanduser().resolve()
    if not folder.is_dir():
        print(f"Error: directory not found: {folder}", file=sys.stderr)
        raise SystemExit(1)
    os.chdir(folder)
    process_videos(folder)
