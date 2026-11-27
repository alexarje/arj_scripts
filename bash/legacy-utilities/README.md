# Legacy Utilities

Small helper scripts from 2015–2019, preserved and documented. These predate the structured tooling in `arj_scripts` but remain useful for quick tasks.

---

## Contents

### Screen Recording

| Script | Description | Dependencies |
|--------|-------------|--------------|
| `byzanz-record-window` | Record a selected window to GIF (10-second delay, click target) | `byzanz`, `xwininfo`, `paplay` |
| `byzanz-record-window-gui` | Same with `gdialog` duration picker and `notify-send` | `byzanz`, `gdialog`, `notify-send` |

```bash
byzanz-record-window 30 output.gif   # 30-second recording
```

⚠️ `byzanz` is unmaintained. If it stops working, consider `peek` or `ffmpeg` + `gifski`.

---

### File Naming

| Script | Description |
|--------|-------------|
| `date-prefix.sh` | **Unified replacement** for `add_date`, `add-date.sh`, `add_today.py` — prefix files with a date stamp |
| `newfile.sh` | Create `YYYY-MM-DD.txt` and open in `$EDITOR` (default: nano) |
| `wordcount` | Count words in one or more files (terminal output) |

```bash
# Prefix with today's date
date-prefix.sh draft.md notes.txt         # → 2026-11-27-draft.md, 2026-11-27-notes.txt

# Custom format
date-prefix.sh -f %y_%m_%d_ draft.md      # → 26_11_27_draft.md

# Batch all .txt files in a folder
date-prefix.sh -f %Y%m%d_ -d . -e '*.txt'

# New daily log file
newfile.sh                                # opens 2026-11-27.txt in $EDITOR
newfile.sh meeting-notes.md               # opens meeting-notes.md in $EDITOR

# Word counts
wordcount chapter1.md chapter2.md         # per-file + total
```

---

### PDF Handling

| Script | Description | Dependencies |
|--------|-------------|--------------|
| `pdfcrop` | Trim PDF margins (wrapper for TeX Live `pdfcrop`) | `texlive-extra-utils` |
| `pdfcrop-multiple.sh` | Batch trim all PDFs in directory | `texlive-extra-utils` |
| `ps2pdf` | Convert PostScript to PDF | `ghostscript` |

```bash
# Trim one PDF
pdfcrop input.pdf output.pdf

# Trim all PDFs in folder
bash pdfcrop-multiple.sh

# Convert PS to PDF
ps2pdf input.ps output.pdf
```

Note: `pdfcrop` is the most reliable tool for trimming academic paper margins.

---

### Data Extraction

| Script | Description |
|--------|-------------|
| `scrapegoogle.sh` | Parse XML/HTML tag-value pairs with pure shell — no Python needed |

```bash
# Extract all <title> tags from an XML file
scrapegoogle.sh file.xml | grep "<title>"

# Output format: <tag>{value}
```

---

## Superseded Scripts (archived in Dropbox only)

These older versions are kept in `Dropbox/development/Bash/` but not migrated — they are replaced by better tools in `arj_scripts`:

| Old Script | Replacement in arj_scripts |
|------------|---------------------------|
| `avi2mp4.sh` (2015) | `bash/avi2mp4.sh` + `bash/avi2mp4_cleanup.sh` |
| `compress-avi-files-in-folder.sh` | `bash/avi2mp4.sh` family |
| `compress_PDF` | `bash/shrinkpdf.sh` |
| `exif_add_datetime` | `bash/images_rename_exif_date.sh` |
| `nautilus-rename-exif-date.py` | `bash/images_rename_exif_date.sh` |
| `sort_images.sh` | `bash/images_resize_1920px-*.sh` |
| `Create_Thumbnail` | `bash/compress-images.sh` |
| `face_detection.sh` / `save_faces.sh` | Python + OpenCV recommended |
| `mxf2mp4.sh` | Unfinished, commented out |
| `pdf2ps.py` | System `pdf2ps` / Poppler utils |
| `add_date` / `add-date.sh` / `add_today.py` | **Unified into `date-prefix.sh`** |
