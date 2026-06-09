#!/usr/bin/env python3
"""
Segment a long conference recording using audio and video cues, then extract salient
frames for each segment.

Segment boundaries come from:
  - Long silent gaps in the audio (session breaks, pauses between talks)
  - Shorter silences paired with a nearby scene change (talk handoffs with new slides)

Within each segment, salient frames are chosen from scene changes plus optional periodic
sampling during visually static stretches.

Example:
  python video_segment_and_extract.py recording.mp4 --dry-run
  python video_segment_and_extract.py recording.mp4 -o analysis/ --detect-from-audio
"""

from __future__ import annotations

import argparse
import csv
import sys
from dataclasses import dataclass
from pathlib import Path

_SCRIPT_DIR = Path(__file__).resolve().parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))

from video_extract_salient_frames import (  # noqa: E402
    FrameCandidate,
    add_periodic_samples,
    detect_scene_changes,
    extract_frames,
    format_timestamp,
    probe_duration,
    select_frames,
)
from video_split_on_silence import (  # noqa: E402
    Segment,
    detection_source,
    export_segment,
    run_ffmpeg_silence_detect,
)


@dataclass(frozen=True)
class SplitGap:
    start: float
    end: float
    duration: float
    reason: str


def scene_near_gap(gap: SplitGap, scene_times: list[float], scene_window: float) -> bool:
    return any(
        gap.start - scene_window <= time <= gap.end + scene_window for time in scene_times
    )


def build_split_gaps(
    silence_gaps: list,
    scene_times: list[float],
    *,
    min_gap: float,
    min_short_gap: float,
    scene_window: float,
    merge_across_longer_than: float | None,
) -> list[SplitGap]:
    split_gaps: list[SplitGap] = []
    for gap in silence_gaps:
        if gap.duration >= min_gap:
            if merge_across_longer_than is not None and gap.duration > merge_across_longer_than:
                continue
            split_gaps.append(
                SplitGap(gap.start, gap.end, gap.duration, reason="silence")
            )
        elif gap.duration >= min_short_gap and scene_near_gap(gap, scene_times, scene_window):
            split_gaps.append(
                SplitGap(gap.start, gap.end, gap.duration, reason="audio_video")
            )
    return split_gaps


def build_combined_segments(
    duration: float,
    split_gaps: list[SplitGap],
    *,
    min_segment: float,
    merge_across_longer_than: float | None,
    all_silence_gaps: list,
) -> list[Segment]:
    split_starts = {gap.start for gap in split_gaps}
    boundaries: list[tuple[float, float]] = []
    cursor = 0.0

    for gap in sorted(all_silence_gaps, key=lambda g: g.start):
        skip_boundary = (
            merge_across_longer_than is not None and gap.duration > merge_across_longer_than
        )
        should_split = gap.start in split_starts
        if should_split and not skip_boundary and gap.start > cursor:
            boundaries.append((cursor, gap.start))
        if skip_boundary:
            continue
        if should_split:
            cursor = max(cursor, gap.end)

    if cursor < duration:
        boundaries.append((cursor, duration))

    segments: list[Segment] = []
    for start, end in boundaries:
        if end - start >= min_segment:
            segments.append(Segment(index=len(segments) + 1, start=start, end=end))
    return segments


def frames_for_segment(
    segment: Segment,
    scene_frames: list[FrameCandidate],
    *,
    min_interval: float,
    periodic_interval: float,
    include_start: bool,
) -> list[FrameCandidate]:
    relative_scenes = [
        FrameCandidate(time=frame.time - segment.start, reason="scene")
        for frame in scene_frames
        if segment.start <= frame.time <= segment.end
    ]
    candidates = add_periodic_samples(relative_scenes, segment.duration, periodic_interval)
    relative = select_frames(
        candidates,
        segment.duration,
        min_interval=min_interval,
        include_start=include_start,
    )
    return [
        FrameCandidate(time=segment.start + frame.time, reason=frame.reason)
        for frame in relative
    ]


def write_segments_manifest(
    manifest_path: Path,
    segments: list[Segment],
    input_path: Path,
    split_gaps: list[SplitGap],
) -> None:
    gap_by_end = {gap.end: gap for gap in split_gaps}
    with manifest_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(
            [
                "segment",
                "start_sec",
                "end_sec",
                "duration_sec",
                "start_time",
                "end_time",
                "split_reason",
                "source",
            ]
        )
        for segment in segments:
            preceding = gap_by_end.get(segment.start)
            split_reason = preceding.reason if preceding else "start"
            writer.writerow(
                [
                    f"{segment.index:03d}",
                    f"{segment.start:.3f}",
                    f"{segment.end:.3f}",
                    f"{segment.duration:.3f}",
                    format_timestamp(segment.start),
                    format_timestamp(segment.end),
                    split_reason,
                    input_path.name,
                ]
            )


def write_segment_frames_manifest(
    manifest_path: Path,
    frames: list[FrameCandidate],
    segment: Segment,
    input_path: Path,
    stem: str,
    image_format: str,
) -> None:
    with manifest_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(
            [
                "segment",
                "frame",
                "time_sec",
                "segment_time_sec",
                "timestamp",
                "segment_timestamp",
                "reason",
                "filename",
                "source",
            ]
        )
        for index, frame in enumerate(frames, start=1):
            segment_time = frame.time - segment.start
            timestamp_slug = format_timestamp(frame.time).replace(":", "-")
            writer.writerow(
                [
                    f"{segment.index:03d}",
                    f"{index:06d}",
                    f"{frame.time:.3f}",
                    f"{segment_time:.3f}",
                    format_timestamp(frame.time),
                    format_timestamp(segment_time),
                    frame.reason,
                    f"{stem}_{index:06d}_{timestamp_slug}.{image_format}",
                    input_path.name,
                ]
            )


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Segment a recording with audio+video cues and extract salient frames per segment.",
    )
    parser.add_argument("input", type=Path, help="Input video file")
    parser.add_argument(
        "-o",
        "--output-dir",
        type=Path,
        help="Output directory (default: <input_stem>_analysis next to input)",
    )

    audio = parser.add_argument_group("audio segmentation")
    audio.add_argument("--noise-db", type=float, default=-50.0)
    audio.add_argument("--min-silence", type=float, default=10.0)
    audio.add_argument("--min-gap", type=float, default=30.0)
    audio.add_argument("--min-short-gap", type=float, default=15.0)
    audio.add_argument(
        "--scene-window",
        type=float,
        default=120.0,
        help="Seconds around a short silence to look for a scene change (default: 120)",
    )
    audio.add_argument("--merge-across-longer-than", type=float, default=None, metavar="SEC")
    audio.add_argument("--detect-from-audio", action="store_true")
    audio.add_argument("--min-segment", type=float, default=180.0)

    video = parser.add_argument_group("video frames")
    video.add_argument("--scene-threshold", type=float, default=0.2)
    video.add_argument("--min-interval", type=float, default=30.0)
    video.add_argument("--periodic-interval", type=float, default=600.0)
    video.add_argument("--no-start-frame", action="store_true")
    video.add_argument("--format", dest="image_format", choices=["jpg", "jpeg", "png"], default="jpg")
    video.add_argument("--max-width", type=int, default=1280)
    video.add_argument("--jpeg-quality", type=int, default=2)

    output = parser.add_argument_group("output")
    output.add_argument(
        "--no-export-segments",
        action="store_true",
        help="Skip writing segment video files; only extract frames",
    )
    output.add_argument("--reencode", action="store_true", help="Re-encode segment videos")
    output.add_argument("--dry-run", action="store_true")
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
        else input_path.parent / f"{input_path.stem}_analysis"
    )
    max_width = None if args.max_width == 0 else args.max_width
    image_format = "jpg" if args.image_format == "jpeg" else args.image_format
    stem = input_path.stem

    detect_path = detection_source(input_path, args.detect_from_audio)
    print(f"Input: {input_path.name}")
    print(
        f"Audio: noise={args.noise_db} dB, min_gap={args.min_gap}s, "
        f"min_short_gap={args.min_short_gap}s, scene_window={args.scene_window}s"
    )
    print(
        f"Video: scene_threshold={args.scene_threshold}, min_interval={args.min_interval}s, "
        f"periodic_interval={args.periodic_interval}s"
    )

    duration = probe_duration(input_path)
    silence_gaps = run_ffmpeg_silence_detect(detect_path, args.noise_db, args.min_silence)
    scene_frames = detect_scene_changes(input_path, args.scene_threshold)
    scene_times = [frame.time for frame in scene_frames]

    split_gaps = build_split_gaps(
        silence_gaps,
        scene_times,
        min_gap=args.min_gap,
        min_short_gap=args.min_short_gap,
        scene_window=args.scene_window,
        merge_across_longer_than=args.merge_across_longer_than,
    )
    segments = build_combined_segments(
        duration,
        split_gaps,
        min_segment=args.min_segment,
        merge_across_longer_than=args.merge_across_longer_than,
        all_silence_gaps=silence_gaps,
    )

    print(
        f"\nDuration: {format_timestamp(duration)} | "
        f"{len(silence_gaps)} silence region(s), {len(scene_frames)} scene change(s)"
    )
    print(f"Using {len(split_gaps)} split point(s) -> {len(segments)} segment(s):\n")

    for gap in split_gaps:
        print(
            f"  split [{gap.reason}] {format_timestamp(gap.start)} -> "
            f"{format_timestamp(gap.end)} ({gap.duration:.1f}s)"
        )
    print()
    for segment in segments:
        frames = frames_for_segment(
            segment,
            scene_frames,
            min_interval=args.min_interval,
            periodic_interval=args.periodic_interval,
            include_start=not args.no_start_frame,
        )
        print(
            f"  {segment.index:03d}  {format_timestamp(segment.start)} -> "
            f"{format_timestamp(segment.end)}  ({segment.duration / 60:.1f} min, "
            f"{len(frames)} frame(s))"
        )

    if args.dry_run:
        print("\nDry run: no files written.")
        return 0

    output_dir.mkdir(parents=True, exist_ok=True)
    write_segments_manifest(output_dir / "segments.csv", segments, input_path, split_gaps)

    if not args.no_export_segments:
        for segment in segments:
            segment_path = output_dir / f"{stem}_{segment.index:03d}.mp4"
            print(f"Writing segment {segment.index:03d} -> {segment_path.name}")
            export_segment(input_path, segment_path, segment, reencode=args.reencode)

    for segment in segments:
        frames = frames_for_segment(
            segment,
            scene_frames,
            min_interval=args.min_interval,
            periodic_interval=args.periodic_interval,
            include_start=not args.no_start_frame,
        )
        if not frames:
            continue

        segment_dir = output_dir / f"segment_{segment.index:03d}" / "frames"
        segment_dir.mkdir(parents=True, exist_ok=True)
        segment_stem = f"{stem}_seg{segment.index:03d}"
        print(
            f"Extracting {len(frames)} frame(s) for segment {segment.index:03d} "
            f"-> {segment_dir}"
        )
        extract_frames(
            input_path,
            segment_dir,
            frames,
            stem=segment_stem,
            image_format=image_format,
            max_width=max_width,
            jpeg_quality=args.jpeg_quality,
        )
        write_segment_frames_manifest(
            segment_dir / "frames.csv",
            frames,
            segment,
            input_path,
            segment_stem,
            image_format,
        )

    print(f"\nDone. Output: {output_dir}")
    print(f"Segments manifest: {output_dir / 'segments.csv'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
