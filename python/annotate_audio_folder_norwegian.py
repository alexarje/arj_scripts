#!/usr/bin/env python3
"""Annotate every audio file in a folder: speech, transcript and laughter, on the GPU.

Built for any folder of recordings --- lectures, interviews, field recordings,
rehearsals. Point it at the folder; it writes the annotations beside each file.

Standalone on purpose. On first run it creates its own environment under
~/.venvs/annotate-audio, installs pinned dependencies (the versions proven on this
machine's RTX GPU), and re-executes itself inside it; after that it starts in seconds.
Copy this one file anywhere and run:

    python3 annotate_audio_folder_norwegian.py /path/to/folder

For every audio file (wav, flac, mp3, m4a, ogg, opus, aiff -- video containers work
too, their audio is used) it writes, beside the file:

    <name>.txt            the transcript as readable text, with timestamps
    <name>.srt            the same as subtitles, ready for any video player
    <name>.eaf            ELAN, three independent tiers: speech, speech_asr, laughter
    <name>.TextGrid       the same in Praat's format
    <name>_annotation.json    every span with scores, plus the parameters used

Already-annotated files are skipped; --force redoes them.

Three methods in here were learned the hard way on a dance corpus and are kept:

- The transcriber runs WITHOUT a VAD filter, so its word timestamps stay on a linear
  clock, and every segment must then overlap an independent speech detection. That
  filter is what removes the "Thank you for watching!" a transcriber invents when made
  to listen to silence.
- A stereo file is not blindly averaged to mono. If the channels do not correlate,
  averaging a microphone with a dead channel halves the level; the louder channel is
  taken instead, and the choice is recorded in the JSON.
- The laughter threshold comes from the score distribution, never from a number that
  looks reasonable: these are sigmoid outputs whose 95th percentile can be 0.011.

This is the NORWEGIAN variant: the transcriber is pinned to Norwegian. Its twin,
annotate_audio_folder_english.py, pins English. Pinning helps single-language material
and hurts mixed-language material; for a multilingual recording, run with
--language auto instead. Whisper large-v3 handles Norwegian well; if you want to try
the National Library's NB-Whisper instead, point --model at a CTranslate2 conversion
of it.
"""
import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

LANGUAGE = "no"

# --------------------------------------------------------------------------- bootstrap
VENV = Path.home() / ".venvs" / "annotate-audio"
PINNED = ["faster-whisper==1.2.1", "ctranslate2==4.8.1", "librosa==1.0.0",
          "soundfile==0.14.0", "panns-inference==0.1.1", "silero-vad>=5.0",
          "torch>=2.3", "numpy"]


def _inside_venv():
    return Path(sys.prefix).resolve() == VENV.resolve()


def _bootstrap():
    import venv as venv_mod

    if not (VENV / "bin" / "python").exists():
        print(f"first run: creating {VENV} and installing the models' dependencies\n"
              f"(a few gigabytes once, including CUDA-enabled torch; later runs "
              f"start in seconds)", flush=True)
        VENV.parent.mkdir(parents=True, exist_ok=True)
        venv_mod.create(VENV, with_pip=True)
        subprocess.run([str(VENV / "bin" / "pip"), "install", "--upgrade", "pip"],
                       check=True)
        subprocess.run([str(VENV / "bin" / "pip"), "install", *PINNED], check=True)
        #: torch pins an older cuDNN wheel that does not ship every sublibrary
        #: (libcudnn_engines_tensor_ir is absent), so the loader falls back to any
        #: system copy and the versions mix. A newer wheel ships the complete set;
        #: cuDNN is compatible within its major version, so the pin warning is noise.
        subprocess.run([str(VENV / "bin" / "pip"), "install", "-U",
                        "nvidia-cudnn-cu13>=9.23"], check=False)
    #: The venv's NVIDIA libraries must win over any system CUDA install: torch
    #: ships a matched cuDNN set, and letting the loader mix it with the system's
    #: gives CUDNN_STATUS_SUBLIBRARY_VERSION_MISMATCH on the first convolution.
    import glob as _glob
    nvidia_libs = sorted(_glob.glob(str(VENV / "lib" / "python3*" / "site-packages"
                                        / "nvidia" / "*" / "lib")))
    env = dict(os.environ)
    env["LD_LIBRARY_PATH"] = os.pathsep.join(
        nvidia_libs + [env.get("LD_LIBRARY_PATH", "")]).rstrip(os.pathsep)
    os.execve(str(VENV / "bin" / "python"), [str(VENV / "bin" / "python"),
                                             os.path.abspath(__file__),
                                             *sys.argv[1:]], env)


if not _inside_venv():
    _bootstrap()

# ------------------------------------------------------------------ inside the venv
import numpy as np  # noqa: E402

AUDIO_EXT = {".wav", ".flac", ".mp3", ".m4a", ".ogg", ".opus", ".aiff", ".aif",
             ".mp4", ".mov", ".mkv", ".avi", ".webm"}


def load_mono(path, sr):
    """The file as mono at `sr`, with the channel decision made and recorded."""
    import librosa
    import soundfile as sf

    try:
        wave, native = sf.read(str(path), always_2d=True)
        wave = wave.T
    except Exception:
        wave, native = librosa.load(str(path), sr=None, mono=False)
        wave = np.atleast_2d(wave)
    if wave.shape[0] == 1:
        mono, how = wave[0], "mono source"
    else:
        a, b = wave[0], wave[1]
        denom = (a.std() * b.std()) or 1e-12
        r = float(np.mean((a - a.mean()) * (b - b.mean())) / denom)
        if r > 0.9:
            mono, how = wave.mean(axis=0), f"channels correlate (r={r:.2f}); averaged"
        else:
            louder = int(np.argmax([np.abs(a).mean(), np.abs(b).mean()]))
            mono = wave[louder]
            how = (f"channels do NOT correlate (r={r:.2f}); took the louder "
                   f"channel ({louder}) instead of averaging")
    if native != sr:
        mono = librosa.resample(mono.astype(np.float32), orig_sr=native, target_sr=sr)
    return mono.astype(np.float32), how


def detect_speech(path):
    """Speech spans from silero-vad, on the 16 kHz mono signal."""
    import torch
    from silero_vad import get_speech_timestamps, load_silero_vad

    wave, how = load_mono(path, 16000)
    model = load_silero_vad()
    stamps = get_speech_timestamps(torch.from_numpy(wave), model,
                                   sampling_rate=16000)
    spans = [{"start": round(s["start"] / 16000, 3),
              "end": round(s["end"] / 16000, 3)} for s in stamps]
    return spans, how


def transcribe(path, language, device, spans):
    """Whisper on the GPU, unfiltered clock, then the overlap filter."""
    from faster_whisper import WhisperModel

    try:
        model = WhisperModel("large-v3", device=device, compute_type="float16")
    except Exception:
        print("    (GPU unavailable for the transcriber; falling back to CPU int8)",
              flush=True)
        model = WhisperModel("large-v3", device="cpu", compute_type="int8")
    lang = None if language == "auto" else language
    segments, info = model.transcribe(str(path), language=lang, vad_filter=False)

    def overlaps(seg):
        return any(seg.start < s["end"] and seg.end > s["start"] for s in spans)

    kept, dropped = [], 0
    for seg in segments:
        text = seg.text.strip()
        if not text:
            continue
        if overlaps(seg):
            kept.append({"start": round(seg.start, 3), "end": round(seg.end, 3),
                         "text": text})
        else:
            dropped += 1
    return kept, dropped, info.language


def detect_laughter(path, device):
    """Laughter scores from PANNs over 2 s windows, thresholded from their own
    distribution. Returns spans and the threshold used, or (None, None) when the
    model is unavailable."""
    try:
        import librosa
        import torch
        from panns_inference import AudioTagging, labels
    except Exception:
        return None, None

    wave, _ = load_mono(path, 32000)
    tagger = AudioTagging(checkpoint_path=None,
                          device="cuda" if device == "cuda" else "cpu")
    idx = [i for i, name in enumerate(labels)
           if "laugh" in name.lower() or "giggle" in name.lower()
           or "chuckle" in name.lower()]
    win, hop = 2 * 32000, 32000
    scores = []
    for start in range(0, max(1, len(wave) - win + 1), hop):
        clip = wave[start:start + win]
        if len(clip) < win:
            clip = np.pad(clip, (0, win - len(clip)))
        (clipwise, _) = tagger.inference(clip[None, :])
        scores.append(float(np.asarray(clipwise)[0, idx].sum()))
    scores = np.asarray(scores)
    if not scores.size:
        return [], 0.0
    threshold = max(float(np.percentile(scores, 98)), 1e-4)
    spans = []
    for i, sc in enumerate(scores):
        if sc >= threshold:
            if spans and i - spans[-1]["_i"] == 1:
                spans[-1]["end"] = round(i * 1.0 + 2.0, 3)
                spans[-1]["_i"] = i
                spans[-1]["score"] = max(spans[-1]["score"], round(sc, 4))
            else:
                spans.append({"start": round(i * 1.0, 3),
                              "end": round(i * 1.0 + 2.0, 3),
                              "score": round(sc, 4), "_i": i})
    for s in spans:
        s.pop("_i")
    return spans, threshold


# ----------------------------------------------------------------------- exporters
def write_eaf(dest, media, duration, tiers):
    """A minimal, valid ELAN file with independent tiers."""
    from xml.sax.saxutils import escape

    slots, lines = {}, []

    def slot(t):
        ms = int(round(t * 1000))
        if ms not in slots:
            slots[ms] = f"ts{len(slots) + 1}"
        return slots[ms]

    ann = 0
    body = []
    for name, spans, key in tiers:
        rows = []
        for s in spans:
            ann += 1
            a, b = slot(s["start"]), slot(s["end"])
            value = escape(str(s.get(key, "")))
            rows.append(f'        <ANNOTATION><ALIGNABLE_ANNOTATION '
                        f'ANNOTATION_ID="a{ann}" TIME_SLOT_REF1="{a}" '
                        f'TIME_SLOT_REF2="{b}"><ANNOTATION_VALUE>{value}'
                        f'</ANNOTATION_VALUE></ALIGNABLE_ANNOTATION></ANNOTATION>')
        body.append(f'    <TIER LINGUISTIC_TYPE_REF="default" TIER_ID="{name}">\n'
                    + "\n".join(rows) + "\n    </TIER>")
    for ms, tid in sorted(slots.items()):
        lines.append(f'        <TIME_SLOT TIME_SLOT_ID="{tid}" TIME_VALUE="{ms}"/>')
    xml = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<ANNOTATION_DOCUMENT AUTHOR="annotate_audio_folder" DATE="2026-08-29T00:00:00+00:00" '
        'FORMAT="3.0" VERSION="3.0">\n'
        f'    <HEADER MEDIA_FILE="" TIME_UNITS="milliseconds">\n'
        f'        <MEDIA_DESCRIPTOR MEDIA_URL="file://{media}" '
        f'MIME_TYPE="audio/x-wav"/>\n    </HEADER>\n'
        '    <TIME_ORDER>\n' + "\n".join(lines) + '\n    </TIME_ORDER>\n'
        + "\n".join(body) + '\n'
        '    <LINGUISTIC_TYPE GRAPHIC_REFERENCES="false" '
        'LINGUISTIC_TYPE_ID="default" TIME_ALIGNABLE="true"/>\n'
        '</ANNOTATION_DOCUMENT>\n')
    Path(dest).write_text(xml, encoding="utf8")


def write_textgrid(dest, duration, tiers):
    """A minimal Praat TextGrid; empty gaps are implicit intervals."""
    out = [f'File type = "ooTextFile"', f'Object class = "TextGrid"', "",
           "xmin = 0", f"xmax = {duration:.3f}", "tiers? <exists>",
           f"size = {len(tiers)}", "item []:"]
    for n, (name, spans, key) in enumerate(tiers, 1):
        cells = []
        cursor = 0.0
        for s in sorted(spans, key=lambda x: x["start"]):
            a, b = max(cursor, s["start"]), min(duration, s["end"])
            if a > cursor:
                cells.append((cursor, a, ""))
            if b > a:
                cells.append((a, b, str(s.get(key, ""))))
                cursor = b
        if cursor < duration:
            cells.append((cursor, duration, ""))
        out += [f"    item [{n}]:", '        class = "IntervalTier"',
                f'        name = "{name}"', "        xmin = 0",
                f"        xmax = {duration:.3f}",
                f"        intervals: size = {len(cells)}"]
        for i, (a, b, text) in enumerate(cells, 1):
            text = text.replace('"', "'")
            out += [f"        intervals [{i}]:", f"            xmin = {a:.3f}",
                    f"            xmax = {b:.3f}", f'            text = "{text}"']
    Path(dest).write_text("\n".join(out) + "\n", encoding="utf8")


def write_srt(dest, segments):
    def stamp(t):
        h, rem = divmod(t, 3600)
        m, s = divmod(rem, 60)
        return f"{int(h):02d}:{int(m):02d}:{int(s):02d},{int((s % 1) * 1000):03d}"

    out = []
    for i, s in enumerate(segments, 1):
        out += [str(i), f"{stamp(s['start'])} --> {stamp(s['end'])}", s["text"], ""]
    Path(dest).write_text("\n".join(out), encoding="utf8")


def write_txt(dest, segments):
    out = []
    for s in segments:
        m, sec = divmod(int(s["start"]), 60)
        h, m = divmod(m, 60)
        out.append(f"[{h:02d}:{m:02d}:{sec:02d}] {s['text']}")
    Path(dest).write_text("\n".join(out) + "\n", encoding="utf8")


# ----------------------------------------------------------------------------- main
def annotate(path, language, force=False):
    import librosa

    stem = path.with_suffix("")
    eaf = stem.with_suffix(".eaf")
    if eaf.exists() and not force:
        print(f"  {path.name}: already annotated, skipped", flush=True)
        return
    try:
        import torch
        device = "cuda" if torch.cuda.is_available() else "cpu"
    except Exception:
        device = "cpu"
    duration = float(librosa.get_duration(path=str(path)))
    print(f"  {path.name}: {duration/60:.1f} min, device={device}", flush=True)

    #: torch first, CTranslate2 last. Both bring a cuDNN, and whichever loads
    #: first wins the process; torch's conv layers refuse a mismatched one
    #: (CUDNN_STATUS_SUBLIBRARY_VERSION_MISMATCH) while CTranslate2 tolerates
    #: torch's. So the torch stages run before Whisper is ever constructed.
    laughter, lthr = detect_laughter(path, device)
    if laughter is None:
        print("    laughter: skipped (panns-inference unavailable)", flush=True)
        laughter = []
    else:
        print(f"    laughter: {len(laughter)} spans at threshold {lthr:.4f} "
              f"(98th percentile of this file's own scores)", flush=True)
    spans, channel_note = detect_speech(path)
    print(f"    speech: {len(spans)} spans ({channel_note})", flush=True)
    asr, dropped, detected = transcribe(path, language, device, spans)
    print(f"    transcript: {len(asr)} segments kept, {dropped} dropped for not "
          f"overlapping a speech detection (language: {detected})", flush=True)

    tiers = [("speech", spans, "none"), ("speech_asr", asr, "text"),
             ("laughter", [dict(s, label=f"?{s['score']:.3f}") for s in laughter],
              "label")]
    write_eaf(eaf, path.resolve(), duration, tiers)
    write_textgrid(stem.with_suffix(".TextGrid"), duration, tiers)
    write_srt(stem.with_suffix(".srt"), asr)
    write_txt(stem.with_suffix(".txt"), asr)
    json.dump({"file": path.name, "duration_s": duration, "language": language,
               "language_detected": detected, "device": device,
               "channel_handling": channel_note,
               "speech": spans, "speech_asr": asr,
               "laughter": laughter, "laughter_threshold": lthr,
               "dropped_asr_segments": dropped,
               "method": ("ASR unfiltered then required to overlap silero-vad; "
                          "laughter PANNs 2 s windows thresholded at the 98th "
                          "percentile of the file's own scores")},
              open(f"{stem}_annotation.json", "w"), indent=1)
    print(f"    written: {stem.name}.txt, .srt, .eaf, .TextGrid, "
          f"_annotation.json", flush=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("folder", type=Path)
    ap.add_argument("--language", default=LANGUAGE,
                    help=f"ISO code or 'auto' (default: {LANGUAGE})")
    ap.add_argument("--force", action="store_true",
                    help="redo files that already have annotations")
    args = ap.parse_args()
    files = sorted(p for p in args.folder.iterdir()
                   if p.suffix.lower() in AUDIO_EXT and p.is_file())
    if not files:
        print(f"no audio files in {args.folder}")
        return 1
    print(f"{len(files)} file(s) in {args.folder}, language={args.language}")
    for p in files:
        annotate(p, args.language, args.force)
    return 0


if __name__ == "__main__":
    sys.exit(main())
