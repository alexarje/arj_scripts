#!/usr/bin/env python3
"""
Split a long video into segments at extended silent gaps (e.g. between conference talks).

Uses ffmpeg's silencedetect filter on the audio track, then cuts the video with stream
copy. Silent gaps are excluded from the output segments.

Example:
  python video_split_on_silence.py recording.mp4 --dry-run
  python video_split_on_silence.py recording.mp4 -o segments/
"""

from __future__ import annotations

import argparse
import csv
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


SILENCE_START_RE = re.compile(r"silence_start:\s*([\d.]+)")
SILENCE_END_RE = re.compile(r"silence_end:\s*([\d.]+)\s*\|\s*silence_duration:\s*([\d.]+)")


@dataclass(frozen=True)
class SilenceGap:
    start: float
    end: float
    duration: float


@dataclass(frozen=True)
class Segment:
    index: int
    start: float
    end: float

    @property
    def duration(self) -> float:
        return self.end - self.start


def run_ffmpeg_silence_detect(
    input_path: Path,
    noise_db: float,
    min_silence: float,
) -> list[SilenceGap]:
    cmd = [
        "ffmpeg",
        "-hide_banner",
        "-nostats",
        "-i",
        str(input_path),
        "-af",
        f"silencedetect=noise={noise_db}dB:d={min_silence}",
        "-f",
        "null",
        "-",
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or "ffmpeg silencedetect failed")

    gaps: list[SilenceGap] = []
    pending_start: float | None = None
    for line in proc.stderr.splitlines():
        start_match = SILENCE_START_RE.search(line)
        if start_match:
            pending_start = float(start_match.group(1))
            continue
        end_match = SILENCE_END_RE.search(line)
        if end_match and pending_start is not None:
            end = float(end_match.group(1))
            duration = float(end_match.group(2))
            gaps.append(SilenceGap(start=pending_start, end=end, duration=duration))
            pending_start = None
    return gaps


def probe_duration(input_path: Path) -> float:
    cmd = [
        "ffprobe",
        "-v",
        "error",
        "-show_entries",
        "format=duration",
        "-of",
        "default=noprint_wrappers=1:nokey=1",
        str(input_path),
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True, check=True)
    return float(proc.stdout.strip())


def build_segments(
    duration: float,
    gaps: list[SilenceGap],
    *,
    min_gap: float,
    min_segment: float,
    merge_across_longer_than: float | None,
) -> list[Segment]:
    split_gaps = [g for g in gaps if g.duration >= min_gap]

    boundaries: list[tuple[float, float]] = []
    cursor = 0.0
    for gap in split_gaps:
        skip_boundary = (
            merge_across_longer_than is not None and gap.duration > merge_across_longer_than
        )
        if not skip_boundary and gap.start > cursor:
            boundaries.append((cursor, gap.start))
        if skip_boundary:
            continue
        cursor = max(cursor, gap.end)
    if cursor < duration:
        boundaries.append((cursor, duration))

    segments: list[Segment] = []
    for start, end in boundaries:
        if end - start >= min_segment:
            segments.append(Segment(index=len(segments) + 1, start=start, end=end))
    return segments


def format_timestamp(seconds: float) -> str:
    total_ms = int(round(seconds * 1000))
    hours, rem_ms = divmod(total_ms, 3_600_000)
    minutes, rem_ms = divmod(rem_ms, 60_000)
    secs, ms = divmod(rem_ms, 1000)
    return f"{hours:02d}:{minutes:02d}:{secs:02d}.{ms:03d}"


def export_segment(
    input_path: Path,
    output_path: Path,
    segment: Segment,
    *,
    reencode: bool,
) -> None:
    cmd = [
        "ffmpeg",
        "-hide_banner",
        "-loglevel",
        "error",
        "-ss",
        f"{segment.start:.3f}",
        "-to",
        f"{segment.end:.3f}",
        "-i",
        str(input_path),
    ]
    if reencode:
        cmd += ["-c:v", "libx264", "-crf", "18", "-preset", "fast", "-c:a", "aac", "-b:a", "192k"]
    else:
        cmd += ["-c", "copy", "-avoid_negative_ts", "make_zero"]
    cmd += ["-movflags", "+faststart", str(output_path)]
    subprocess.run(cmd, check=True)


def write_manifest(manifest_path: Path, segments: list[Segment], input_path: Path) -> None:
    with manifest_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["segment", "start_sec", "end_sec", "duration_sec", "start_time", "end_time", "source"])
        for segment in segments:
            writer.writerow(
                [
                    f"{segment.index:03d}",
                    f"{segment.start:.3f}",
                    f"{segment.end:.3f}",
                    f"{segment.duration:.3f}",
                    format_timestamp(segment.start),
                    format_timestamp(segment.end),
                    input_path.name,
                ]
            )


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Split a video into segments at long silent gaps between presentations.",
    )
    parser.add_argument("input", type=Path, help="Input video file")
    parser.add_argument(
        "-o",
        "--output-dir",
        type=Path,
        help="Directory for output segments (default: <input_stem>_segments next to input)",
    )
    parser.add_argument(
        "--noise-db",
        type=float,
        default=-50.0,
        help="Silence threshold in dB (default: -50). Lower = more sensitive.",
    )
    parser.add_argument(
        "--min-silence",
        type=float,
        default=10.0,
        help="Minimum continuous silence ffmpeg must detect, in seconds (default: 10)",
    )
    parser.add_argument(
        "--min-gap",
        type=float,
        default=30.0,
        help="Only split on silences at least this long, in seconds (default: 30)",
    )
    parser.add_argument(
        "--merge-across-longer-than",
        type=float,
        default=None,
        metavar="SEC",
        help="Do not split at silences longer than SEC (keeps lunch/stream-off breaks in one segment)",
    )
    parser.add_argument(
        "--detect-from-audio",
        action="store_true",
        help="Run silence detection on a sibling .aac/.m4a/.wav file if present (faster)",
    )
    parser.add_argument(
        "--min-segment",
        type=float,
        default=180.0,
        help="Drop output segments shorter than this, in seconds (default: 180)",
    )
    parser.add_argument(
        "--reencode",
        action="store_true",
        help="Re-encode segments for frame-accurate cuts (slower, larger job)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Detect segments and print them without creating video files",
    )
    return parser.parse_args(argv)


def detection_source(input_path: Path, use_audio: bool) -> Path:
    if not use_audio:
        return input_path
    for ext in (".aac", ".m4a", ".wav", ".mp3", ".flac"):
        candidate = input_path.with_suffix(ext)
        if candidate.is_file():
            return candidate
    return input_path


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    input_path = args.input.expanduser().resolve()
    if not input_path.is_file():
        print(f"Input file not found: {input_path}", file=sys.stderr)
        return 1

    output_dir = (
        args.output_dir.expanduser().resolve()
        if args.output_dir
        else input_path.parent / f"{input_path.stem}_segments"
    )

    detect_path = detection_source(input_path, args.detect_from_audio)
    print(f"Analyzing silence in: {detect_path.name}")
    print(
        f"  noise={args.noise_db} dB, min_silence={args.min_silence}s, "
        f"min_gap={args.min_gap}s, min_segment={args.min_segment}s"
    )
    if args.merge_across_longer_than is not None:
        print(
            f"  merge_across_longer_than={args.merge_across_longer_than}s "
            "(not splitting at longer silences)"
        )

    gaps = run_ffmpeg_silence_detect(detect_path, args.noise_db, args.min_silence)
    duration = probe_duration(input_path)
    segments = build_segments(
        duration,
        gaps,
        min_gap=args.min_gap,
        min_segment=args.min_segment,
        merge_across_longer_than=args.merge_across_longer_than,
    )

    print(f"\nDetected {len(gaps)} silent region(s), using {len(segments)} segment(s):\n")
    for gap in gaps:
        is_split = gap.duration >= args.min_gap and (
            args.merge_across_longer_than is None or gap.duration <= args.merge_across_longer_than
        )
        marker = " *" if is_split else ""
        print(
            f"  gap {format_timestamp(gap.start)} -> {format_timestamp(gap.end)} "
            f"({gap.duration:.1f}s){marker}"
        )
    print()
    for segment in segments:
        print(
            f"  {segment.index:03d}  {format_timestamp(segment.start)} -> "
            f"{format_timestamp(segment.end)}  ({segment.duration / 60:.1f} min)"
        )

    if args.dry_run:
        print("\nDry run: no files written.")
        return 0

    output_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = output_dir / "segments.csv"
    write_manifest(manifest_path, segments, input_path)

    stem = input_path.stem
    for segment in segments:
        output_path = output_dir / f"{stem}_{segment.index:03d}.mp4"
        print(f"Writing {output_path.name} ...")
        export_segment(input_path, output_path, segment, reencode=args.reencode)

    print(f"\nDone. Wrote {len(segments)} segment(s) to {output_dir}")
    print(f"Manifest: {manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
