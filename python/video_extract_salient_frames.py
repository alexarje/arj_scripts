#!/usr/bin/env python3
"""
Extract salient still frames from long recordings (e.g. conference streams).

Designed for videos that are mostly people talking with occasional slide or camera
changes. Frames are selected when the picture changes significantly (ffmpeg scene
detection), with optional periodic sampling during long visually static stretches.

Example:
  python video_extract_salient_frames.py recording.mp4 --dry-run
  python video_extract_salient_frames.py recording.mp4 -o frames/ --scene-threshold 0.2
"""

from __future__ import annotations

import argparse
import csv
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


PTS_TIME_RE = re.compile(r"pts_time:([\d.]+)")

REASON_PRIORITY = {"scene": 2, "periodic": 1, "start": 0}


@dataclass(frozen=True)
class FrameCandidate:
    time: float
    reason: str
    scene_score: float | None = None


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


def detect_scene_changes(input_path: Path, scene_threshold: float) -> list[FrameCandidate]:
    cmd = [
        "ffmpeg",
        "-hide_banner",
        "-nostats",
        "-i",
        str(input_path),
        "-vf",
        f"select='gt(scene,{scene_threshold})',showinfo",
        "-f",
        "null",
        "-",
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or "ffmpeg scene detection failed")

    candidates: list[FrameCandidate] = []
    for line in proc.stderr.splitlines():
        if "pts_time:" not in line:
            continue
        match = PTS_TIME_RE.search(line)
        if match:
            candidates.append(FrameCandidate(time=float(match.group(1)), reason="scene"))
    return candidates


def add_periodic_samples(
    candidates: list[FrameCandidate],
    duration: float,
    periodic_interval: float,
) -> list[FrameCandidate]:
    if periodic_interval <= 0:
        return list(candidates)

    times = sorted({0.0, *[c.time for c in candidates], duration})
    extras: list[FrameCandidate] = []
    for start, end in zip(times, times[1:]):
        if end - start <= periodic_interval:
            continue
        tick = start + periodic_interval
        while tick < end - 1.0:
            extras.append(FrameCandidate(time=tick, reason="periodic"))
            tick += periodic_interval
    return list(candidates) + extras


def select_frames(
    candidates: list[FrameCandidate],
    duration: float,
    *,
    min_interval: float,
    include_start: bool,
) -> list[FrameCandidate]:
    pool = list(candidates)
    if include_start:
        pool.append(FrameCandidate(time=0.0, reason="start"))

    pool = sorted(pool, key=lambda c: (-REASON_PRIORITY.get(c.reason, 0), c.time))
    selected: list[FrameCandidate] = []
    for candidate in pool:
        if candidate.time < 0 or candidate.time > duration:
            continue
        if any(abs(candidate.time - kept.time) < min_interval for kept in selected):
            continue
        selected.append(candidate)
    return sorted(selected, key=lambda c: c.time)


def format_timestamp(seconds: float) -> str:
    total_ms = int(round(seconds * 1000))
    hours, rem_ms = divmod(total_ms, 3_600_000)
    minutes, rem_ms = divmod(rem_ms, 60_000)
    secs, ms = divmod(rem_ms, 1000)
    return f"{hours:02d}:{minutes:02d}:{secs:02d}.{ms:03d}"


def extract_frames(
    input_path: Path,
    output_dir: Path,
    frames: list[FrameCandidate],
    *,
    stem: str,
    image_format: str,
    max_width: int | None,
    jpeg_quality: int,
) -> None:
    if not frames:
        return

    scale = f"scale='min({max_width},iw)':-2" if max_width else "scale=iw:ih"
    for index, frame in enumerate(frames, start=1):
        timestamp_slug = format_timestamp(frame.time).replace(":", "-")
        output_path = output_dir / f"{stem}_{index:06d}_{timestamp_slug}.{image_format}"
        cmd = [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-ss",
            f"{frame.time:.3f}",
            "-i",
            str(input_path),
            "-frames:v",
            "1",
            "-vf",
            scale,
        ]
        if image_format == "jpg":
            cmd += ["-q:v", str(jpeg_quality)]
        cmd.append(str(output_path))
        subprocess.run(cmd, check=True)
        if index % 20 == 0 or index == len(frames):
            print(f"  {index}/{len(frames)} frames written")


def write_manifest(manifest_path: Path, frames: list[FrameCandidate], input_path: Path) -> None:
    with manifest_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["index", "time_sec", "timestamp", "reason", "filename", "source"])
        for index, frame in enumerate(frames, start=1):
            timestamp_slug = format_timestamp(frame.time).replace(":", "-")
            writer.writerow(
                [
                    f"{index:06d}",
                    f"{frame.time:.3f}",
                    format_timestamp(frame.time),
                    frame.reason,
                    f"{input_path.stem}_{index:06d}_{timestamp_slug}",
                    input_path.name,
                ]
            )


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Extract salient still frames from long talking-head / slide videos.",
    )
    parser.add_argument("input", type=Path, help="Input video file")
    parser.add_argument(
        "-o",
        "--output-dir",
        type=Path,
        help="Output directory (default: <input_stem>_frames next to input)",
    )
    parser.add_argument(
        "--scene-threshold",
        type=float,
        default=0.2,
        help="Scene-change sensitivity, 0-1 (default: 0.2). Lower = more frames.",
    )
    parser.add_argument(
        "--min-interval",
        type=float,
        default=30.0,
        help="Minimum seconds between extracted frames (default: 30)",
    )
    parser.add_argument(
        "--periodic-interval",
        type=float,
        default=600.0,
        help="Also sample every N seconds during long static stretches (default: 600). Use 0 to disable.",
    )
    parser.add_argument(
        "--no-start-frame",
        action="store_true",
        help="Do not force-include a frame at t=0",
    )
    parser.add_argument(
        "--format",
        dest="image_format",
        choices=["jpg", "jpeg", "png"],
        default="jpg",
        help="Output image format (default: jpg)",
    )
    parser.add_argument(
        "--max-width",
        type=int,
        default=1280,
        help="Resize frames to this max width in pixels (default: 1280). Use 0 for full size.",
    )
    parser.add_argument(
        "--jpeg-quality",
        type=int,
        default=2,
        help="JPEG quality for ffmpeg -q:v, 2 (best) to 31 (default: 2)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Detect frames and print them without writing images",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    input_path = args.input.expanduser().resolve()
    if not input_path.is_file():
        print(f"Input file not found: {input_path}", file=sys.stderr)
        return 1

    output_dir = (
        args.output_dir.expanduser().resolve()
        if args.output_dir
        else input_path.parent / f"{input_path.stem}_frames"
    )
    max_width = None if args.max_width == 0 else args.max_width
    image_format = "jpg" if args.image_format == "jpeg" else args.image_format

    print(f"Detecting visual changes in: {input_path.name}")
    print(
        f"  scene_threshold={args.scene_threshold}, min_interval={args.min_interval}s, "
        f"periodic_interval={args.periodic_interval}s"
    )

    duration = probe_duration(input_path)
    scene_frames = detect_scene_changes(input_path, args.scene_threshold)
    all_candidates = add_periodic_samples(scene_frames, duration, args.periodic_interval)
    frames = select_frames(
        all_candidates,
        duration,
        min_interval=args.min_interval,
        include_start=not args.no_start_frame,
    )

    scene_count = sum(1 for frame in frames if frame.reason == "scene")
    periodic_count = sum(1 for frame in frames if frame.reason == "periodic")
    start_count = sum(1 for frame in frames if frame.reason == "start")
    print(
        f"\nDuration: {format_timestamp(duration)} | "
        f"{len(scene_frames)} scene change(s) -> {len(frames)} frame(s) "
        f"({scene_count} scene, {periodic_count} periodic, {start_count} start)\n"
    )
    for index, frame in enumerate(frames, start=1):
        print(f"  {index:04d}  {format_timestamp(frame.time)}  [{frame.reason}]")

    if args.dry_run:
        print("\nDry run: no files written.")
        return 0

    output_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = output_dir / "frames.csv"
    write_manifest(manifest_path, frames, input_path)

    print(f"\nExtracting {len(frames)} frame(s) to {output_dir} ...")
    extract_frames(
        input_path,
        output_dir,
        frames,
        stem=input_path.stem,
        image_format=image_format,
        max_width=max_width,
        jpeg_quality=args.jpeg_quality,
    )

    print(f"Done. Manifest: {manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
