#!/usr/bin/env python3
"""
Generate AI captions for images and optionally write them as alt text.

Requirements:
  pip install transformers torch pillow requests tqdm

Usage:
  python3 scripts/generate_alt_text_ai.py         # dry-run; writes alt_ai_report.csv
  python3 scripts/generate_alt_text_ai.py --apply # apply changes (creates .bak files)
  python3 scripts/generate_alt_text_ai.py --help

Notes:
- By default the script tries to use a local HF model via transformers pipeline.
- If you set the environment variable HF_API_TOKEN, it will instead call the Hugging Face Inference API.
- Running a local model requires downloading model weights and may need GPU for speed.
"""
import argparse
import csv
import os
import re
from pathlib import Path
from typing import List, Tuple
from PIL import Image
import requests
from tqdm import tqdm

MD_GLOB = "content/**/*.md"
REPORT_CSV = "alt_ai_report.csv"

# Regular expressions
MD_IMG_RE = re.compile(r'!\[([^\]]*)\]\(([^) ]+)(?:\s+"[^"]*")?\)')
HTML_IMG_RE = re.compile(r'<img\b[^>]*>', flags=re.I)
SRC_RE = re.compile(r'src=["\']([^"\']+)["\']', flags=re.I)
ALT_RE = re.compile(r'alt=["\']([^"\']*)["\']', flags=re.I)

# Try to import transformers pipeline lazily
def get_captioner_local():
    try:
        from transformers import pipeline, AutoImageProcessor
        from PIL import Image
        model_id = "nlpconnect/vit-gpt2-image-captioning"

        # Prefer fast processor if available, otherwise None (pipeline falls back)
        proc = None
        try:
            proc = AutoImageProcessor.from_pretrained(model_id, use_fast=True)
        except Exception:
            proc = None

        pipe = pipeline("image-to-text", model=model_id, feature_extractor=proc)

        tok = getattr(pipe, "tokenizer", None)
        mdl = getattr(pipe, "model", None)

        # Ensure a real pad token is present and update model config accordingly.
        if tok is not None:
            # If pad token missing or equals eos, add a dedicated pad token
            needs_pad = (tok.pad_token is None) or (tok.pad_token == tok.eos_token)
            if needs_pad:
                try:
                    tok.add_special_tokens({"pad_token": "<pad>"})
                except Exception:
                    tok.pad_token = tok.eos_token
            # Ensure tokenizer has pad_token_id set
            if getattr(tok, "pad_token_id", None) is None:
                tok.pad_token_id = tok.convert_tokens_to_ids(tok.pad_token)
            # Ensure model config uses the same pad_token_id
            if mdl is not None and getattr(mdl.config, "pad_token_id", None) is None:
                mdl.config.pad_token_id = tok.pad_token_id

        def caption(img_path):
            if isinstance(img_path, (str, Path)):
                img = Image.open(str(img_path)).convert("RGB")
            elif hasattr(img_path, "read"):
                img = Image.open(img_path).convert("RGB")
            else:
                img = img_path
            out = pipe(img)
            if isinstance(out, list) and out:
                first = out[0]
                if isinstance(first, dict):
                    return first.get("generated_text") or first.get("caption") or str(first)
                return str(first)
            if isinstance(out, dict):
                return out.get("generated_text") or out.get("caption") or str(out)
            return str(out)

        return caption
    except Exception:
        return None

# Hugging Face Inference API fallback
HF_API_URL = "https://api-inference.huggingface.co/models/nlpconnect/vit-gpt2-image-captioning"
def caption_via_hf_api(image_path, token):
    headers = {"Authorization": f"Bearer {token}"}
    with open(image_path, "rb") as f:
        data = f.read()
    resp = requests.post(HF_API_URL, headers=headers, data=data, timeout=60)
    resp.raise_for_status()
    out = resp.json()
    if isinstance(out, list) and len(out) and "generated_text" in out[0]:
        return out[0]["generated_text"]
    # fallback if API returns a different schema
    if isinstance(out, dict) and "error" in out:
        raise RuntimeError(out["error"])
    return str(out)

def find_images_in_markdown(text: str) -> List[Tuple[str,str,int]]:
    """
    Return list of tuples: (kind, src, span_start_index)
    kind is "md" or "html"
    """
    results = []
    for m in MD_IMG_RE.finditer(text):
        alt, src = m.group(1), m.group(2)
        results.append(("md", src, m.start()))
    for m in HTML_IMG_RE.finditer(text):
        tag = m.group(0)
        s = SRC_RE.search(tag)
        if s:
            results.append(("html", s.group(1), m.start()))
    return results

def resolve_image_path(src: str, md_path: Path) -> Path:
    # handle absolute-ish paths starting with /static or /images by assuming repo root static/
    p = src.split("?")[0].split("#")[0]
    if p.startswith("http://") or p.startswith("https://"):
        return None
    if p.startswith("/"):
        # try static/ then root
        candidates = [Path("static") / p.lstrip("/"), Path(p.lstrip("/"))]
    else:
        candidates = [md_path.parent / p, Path("static") / p, Path(p)]
    for c in candidates:
        if c.exists():
            return c
    return candidates[0]  # return best guess even if missing

def process_file(path: Path, caption_func, token, apply=False):
    txt = path.read_text(encoding="utf-8")
    images = find_images_in_markdown(txt)
    changes = []
    for kind, src, _ in images:
        # find the match & current alt (may be empty)
        if kind == "md":
            m = MD_IMG_RE.search(txt, pos=_)
            if not m:
                continue
            old_alt = m.group(1)
        else:
            m = HTML_IMG_RE.search(txt, pos=_)
            if not m:
                continue
            tag = m.group(0)
            alt_m = ALT_RE.search(tag)
            old_alt = alt_m.group(1) if alt_m else ""

        # resolve image path (local) or leave None for remote
        img_path = resolve_image_path(src, path)
        caption = ""
        if img_path and img_path.exists():
            try:
                if caption_func:
                    caption = caption_func(img_path)
                elif token:
                    caption = caption_via_hf_api(img_path, token)
                else:
                    caption = ""
            except Exception as e:
                caption = f"(error: {e})"
        else:
            # remote image: try HF API only if token provided
            if token and src.startswith("http"):
                try:
                    r = requests.get(src, timeout=20)
                    r.raise_for_status()
                    import tempfile
                    with tempfile.NamedTemporaryFile(delete=False) as tf:
                        tf.write(r.content)
                        tf.flush()
                        caption = caption_via_hf_api(tf.name, token)
                        os.unlink(tf.name)
                except Exception as e:
                    caption = f"(error: {e})"
            else:
                caption = ""

        changes.append((path, kind, src, str(old_alt), caption))

        # If applying, overwrite existing alt (only if caption non-empty)
        if apply and caption:
            if kind == "md":
                txt = txt[:m.start()] + f'![{caption}]({src})' + txt[m.end():]
            else:
                tag = m.group(0)
                if ALT_RE.search(tag):
                    new_tag = ALT_RE.sub(f'alt="{caption}"', tag)
                else:
                    new_tag = tag.rstrip('>')
                    new_tag += f' alt="{caption}">'
                txt = txt[:m.start()] + new_tag + txt[m.end():]

    # Write file backup and new content if apply and changed
    if apply and txt != path.read_text(encoding="utf-8"):
        bak = path.with_suffix(path.suffix + ".bak")
        bak.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")
        path.write_text(txt, encoding="utf-8")
    return changes

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true", help="Apply changes (create .bak files).")
    parser.add_argument("--report", default=REPORT_CSV)
    args = parser.parse_args()

    hf_token = os.environ.get("HF_API_TOKEN")
    caption_func = None
    if not hf_token:
        caption_func = get_captioner_local()
        if caption_func is None:
            print("No local captioner available. Set HF_API_TOKEN to use HF Inference API, or install transformers and model weights.")
            print("Proceeding in dry-run mode; captions will be empty for missing captioners.")
    else:
        print("HF_API_TOKEN provided: will use Hugging Face Inference API for captions.")

    md_files = sorted(Path(".").glob(MD_GLOB))
    all_changes = []
    for md in tqdm(md_files, desc="Scanning markdown"):
        changes = process_file(md, caption_func, hf_token, apply=args.apply)
        all_changes.extend(changes)

    # write CSV
    with open(args.report, "w", newline="", encoding="utf-8") as f:
        import csv
        w = csv.writer(f)
        w.writerow(["file", "kind", "src", "old_alt", "ai_caption"])
        for path, kind, src, old_alt, caption in all_changes:
            w.writerow([str(path), kind, src, old_alt, caption])

    print(f"Done. Found {len(all_changes)} images without alt text. Report: {args.report}")
    if not args.apply:
        print("Run with --apply to insert captions (backups created with .bak).")

if __name__ == "__main__":
    main()