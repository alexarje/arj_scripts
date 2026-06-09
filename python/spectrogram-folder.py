#!/usr/bin/env python3
"""Generate mel spectrogram PNGs for audio files in a directory."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


def convert_m4a_to_wav(src_file: Path) -> Path:
    from pydub import AudioSegment
    dst_file = src_file.with_suffix(".wav")
    audio = AudioSegment.from_file(src_file, format="m4a")
    audio.export(dst_file, format="wav")
    return dst_file


def create_spectrogram(filepath: Path, output_dir: Path) -> None:
    import librosa
    import librosa.display
    import matplotlib.pyplot as plt
    import numpy as np

    print(f"Processing {filepath}")
    wav_filepath = filepath
    converted = False

    if filepath.suffix.lower() == ".m4a":
        try:
            wav_filepath = convert_m4a_to_wav(filepath)
            converted = True
        except Exception as exc:
            print(f"Error converting {filepath}: {exc}", file=sys.stderr)
            return

    try:
        y, sr = librosa.load(wav_filepath, sr=None)
        spectrogram = librosa.feature.melspectrogram(y=y, sr=sr)
        spectrogram_db = librosa.power_to_db(spectrogram, ref=np.max)
    except Exception as exc:
        print(f"Error processing {wav_filepath}: {exc}", file=sys.stderr)
        return
    finally:
        if converted and wav_filepath.exists():
            wav_filepath.unlink()

    plt.figure(figsize=(16, 9))
    librosa.display.specshow(spectrogram_db, sr=sr, x_axis="time", y_axis="mel")
    plt.colorbar(format="%+2.0f dB")
    plt.title("Mel-frequency spectrogram")

    output_filepath = output_dir / f"{filepath.stem}_spectrogram.png"
    plt.savefig(output_filepath)
    plt.close()
    print(f"Saved spectrogram to {output_filepath}")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create spectrogram PNGs for audio files.")
    parser.add_argument(
        "input_dir",
        nargs="?",
        type=Path,
        default=Path("."),
        help="Directory with audio files (default: current directory)",
    )
    parser.add_argument(
        "-o",
        "--output-dir",
        type=Path,
        default=None,
        help="Output directory (default: same as input directory)",
    )
    return parser.parse_args(argv)


def main() -> int:
    args = parse_args()
    input_dir = args.input_dir.expanduser().resolve()
    output_dir = (args.output_dir or input_dir).expanduser().resolve()

    if not input_dir.is_dir():
        print(f"Error: directory not found: {input_dir}", file=sys.stderr)
        return 1

    output_dir.mkdir(parents=True, exist_ok=True)
    audio_files = sorted(
        path
        for path in input_dir.iterdir()
        if path.is_file() and path.suffix.lower() in {".wav", ".mp3", ".flac", ".ogg", ".m4a"}
    )
    if not audio_files:
        print(f"No audio files found in {input_dir}", file=sys.stderr)
        return 1

    for filepath in audio_files:
        create_spectrogram(filepath, output_dir)

    print("Spectrogram creation process completed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
