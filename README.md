# arj_scripts

Personal utility scripts for media processing, document handling, and filesystem reporting. Developed for Ubuntu.

Most bash scripts process all matching files in the **current directory** or a **folder you pass as an argument**. Python scripts generally take explicit CLI arguments — run any script with `--help` where available.

## Requirements

### System tools (common)

| Tool | Used for |
|------|----------|
| [ffmpeg](https://ffmpeg.org/) / ffprobe | Video and audio processing |
| [ImageMagick](https://imagemagick.org/) | Image resize, collage, montage |
| [exiftool](https://exiftool.org/) | EXIF-based renaming |
| [poppler-utils](https://poppler.freedesktop.org/) | `pdftotext`, `pdfimages`, `pdfunite` |
| jpegoptim, optipng, jhead | Image optimization |
| wkhtmltopdf | HTML to PDF |

Install the basics on Ubuntu:

```bash
sudo apt install ffmpeg imagemagick exiftool poppler-utils jpegoptim optipng jhead wkhtmltopdf
```

### Python packages (optional, per script)

Only install what you need:

```bash
# Conference / recording (stdlib only — ffmpeg must be on PATH)
python3 python/video_segment_and_extract.py --help

# Video analysis & plots
pip install numpy matplotlib librosa

# Musicalgestures video analysis
pip install musicalgestures

# PDF tools
pip install PyPDF2 reportlab fpdf2

# AI alt-text generation
pip install transformers torch pillow requests tqdm
```

## Repository layout

```
arj_scripts/
├── bash/          # Shell scripts (batch-oriented)
├── python/        # Python scripts (CLI-oriented)
└── LICENSE        # GPLv3
```

## Conference / recording pipeline

Scripts for splitting long streams (talks, symposiums) and extracting representative stills.

| Script | Description |
|--------|-------------|
| [`python/video_split_on_silence.py`](python/video_split_on_silence.py) | Split a recording at long silent gaps |
| [`python/video_extract_salient_frames.py`](python/video_extract_salient_frames.py) | Extract stills at slide/camera changes |
| [`python/video_segment_and_extract.py`](python/video_segment_and_extract.py) | **Combined**: segment with audio+video cues, then extract frames per segment |

Typical workflow:

```bash
# Preview segmentation and frame counts
python3 python/video_segment_and_extract.py recording.mp4 --detect-from-audio --dry-run

# Full analysis: segment videos + per-segment frames
python3 python/video_segment_and_extract.py recording.mp4 --detect-from-audio -o analysis/

# Or use the individual tools
python3 python/video_split_on_silence.py recording.mp4 --detect-from-audio -o segments/
python3 python/video_extract_salient_frames.py recording.mp4 -o frames/
```

**Segmentation signals**

- **Audio**: long silences (breaks between talks/sessions)
- **Audio + video**: shorter silences paired with a nearby scene change (talk handoffs)
- **Frames**: scene changes within each segment, plus periodic samples during static stretches

## Bash scripts

### Video — merge, transcode, export

| Script | Description |
|--------|-------------|
| `video_merge_files.sh` | Concatenate videos in cwd → `output.mp4` |
| `video_merge_files_gpu.sh` | Merge with optional GPU re-encode (`--gpu`, `--reencode`) |
| `video_merge_files_compress_h265.sh` | Merge to a single H.265 file |
| `video_resize_hd.sh` | Resize all `.mp4` in cwd to 1080p/25fps (NVENC) |
| `video_normalize_audio.sh` | Loudness-normalize audio → `*_norm.mp4` |
| `video_audio_export.sh` | Extract audio from each `.mp4` → `.aac` |
| `split_video_left_right.sh` | Split one video into left/right halves |

### Video — 360° / fisheye / Insta360

| Script | Description |
|--------|-------------|
| `insta360-to-equirectangular.sh` | Convert Insta360 `.insp` to equirectangular JPG |
| `insp_timelapse.sh` | Build timelapse MP4 from `.insp` folder |
| `defisheye_views.sh` | Generate rectilinear views from fisheye video |

### Images

| Script | Description |
|--------|-------------|
| `resize-images.sh` | Resize JPGs in a folder to 640px width |
| `images_resize_1920px-rename.sh` | Resize to max 1920px → `*_optimized` copies |
| `images_resize_1920px-overwrite.sh` | Same, but overwrites originals |
| `compress-images.sh` | Optimize PNGs with optipng |
| `images_rename_exif_date.sh` | Rename JPEGs to `YYYYMMDD_HHMMSS` from EXIF |
| `create_collage.sh` | Build PNG collages (5×8 grid) from a folder |

Image folder scripts accept an optional directory argument (default: current directory):

```bash
bash/images_resize_1920px-rename.sh ~/Pictures/event
```

### Audio

| Script | Description |
|--------|-------------|
| `audio_convert_flac.sh` | Concatenate WAVs in cwd → single 48 kHz FLAC |

### PDF / documents

| Script | Description |
|--------|-------------|
| `count_words_pdf.sh` | Word count per PDF in a folder |
| `html-to-pdf.sh` | Convert HTML files in a folder and merge to one PDF |
| `extract_images.sh` | Extract embedded images from a PDF |

### Filesystem / web

| Script | Description |
|--------|-------------|
| `folder_report.sh` | File counts, sizes, and owners by media type |
| `file_types.sh` | Count files by extension under a directory |
| `web_video_download.sh` | Scrape video URLs from a page and download with wget |

## Python scripts

### Video analysis

| Script | Description | Packages |
|--------|-------------|----------|
| `video_timeline_plot.py` | Videogram + waveform timeline plot | numpy, matplotlib, librosa |
| `videoanalysis.py` | Musicalgestures visualizations (directograms, motion, etc.) | musicalgestures |
| `spectrogram-folder.py` | Mel spectrogram PNGs for audio files in cwd | librosa, matplotlib, pydub |

### PDF / documents

| Script | Description | Packages |
|--------|-------------|----------|
| `word_count_pdf.py` | Rank PDFs in a folder by word count | PyPDF2 |
| `text_to_pdf.py` | Compile text files in a folder into one PDF with TOC | reportlab |
| `folder_report_pdf.py` | PDF folder inventory with pie charts | matplotlib, fpdf |

### Filesystem

| Script | Description |
|--------|-------------|
| `folder_report.py` | Text folder inventory (Python version of `folder_report.sh`) |

### Images / web

| Script | Description | Packages |
|--------|-------------|----------|
| `generate_alt_text.py` | AI image captions for Hugo markdown | transformers, torch |
| `transparent-circle.py` | Pillow example snippet (circular alpha mask) — not a CLI tool |

## Conventions

- **Batch bash scripts** loop over `*.mp4`, `*.jpg`, etc. in the current working directory unless a folder argument is documented.
- **Python CLIs** use `argparse`; prefer `--dry-run` on the conference scripts to preview before writing files.
- **ffmpeg** is used throughout; GPU scripts need appropriate drivers (NVENC, VAAPI, etc.).
- Several bash/Python pairs overlap (`folder_report`, PDF word counts) — use whichever fits your workflow.

## License

GPLv3 — see [LICENSE](LICENSE).
