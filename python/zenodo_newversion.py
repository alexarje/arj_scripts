#!/usr/bin/env python3
"""Publish a new version of an existing Zenodo record, replacing only what changed.

    python3 ~/zenodo_newversion.py                 # dry run: says what it would do
    python3 ~/zenodo_newversion.py --go            # creates the draft and uploads
    python3 ~/zenodo_newversion.py --go --publish  # ...and publishes it
    python3 ~/zenodo_newversion.py --fix 22134130            # repair an existing draft
    python3 ~/zenodo_newversion.py --fix 22134130 --publish  # ...and publish it

**Draft and publish are separate on purpose.** Publishing mints a permanent DOI and cannot
be undone, so the default is to leave a draft you can look at on the website first. Run
again with --publish once you are happy, or press publish there.

Zenodo's new-version mechanism copies every file from the previous version, so only the
files that changed are deleted and re-uploaded. Here that is three of eight: the 6.6 GB
of concert, documentation and experiment archives are never re-transferred.

Written 2026-08-27 for the Westney deposit. The token is read from ~/.zenodo_token.
"""
import json
import os
import sys
import urllib.error
import urllib.request

RECORD = 21354402
STAGE = ("/tmp/claude-1000/-media-alexanje-Seagate-Hub-aktiv-HybridDanceImprov/"
         "1b2b9b84-a97c-492d-894a-a2334cc31e13/scratchpad/upload")

#: What changed in this version. Everything else is carried over by Zenodo untouched.
REPLACE = ["README.md", "rehearsal.zip", "CITATION.cff", "zenodo-metadata.json"]
ADD = ["SHA256SUMS.txt"]
NEW_VERSION = "2.1"


def token():
    path = os.path.expanduser("~/.zenodo_token")
    if not os.path.exists(path):
        sys.exit("no ~/.zenodo_token")
    with open(path) as fh:
        return fh.read().strip()


def api(method, url, tok, data=None, headers=None):
    sep = "&" if "?" in url else "?"
    req = urllib.request.Request(f"{url}{sep}access_token={tok}", method=method)
    body = None
    if data is not None:
        body = json.dumps(data).encode()
        req.add_header("Content-Type", "application/json")
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, body, timeout=120) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        sys.exit(f"{method} {url}\n  HTTP {e.code}: {e.read().decode()[:500]}")


def put_file(bucket, name, path, tok):
    size = os.path.getsize(path)
    print(f"   uploading {name} ({size / 1e6:.1f} MB)...", flush=True)
    with open(path, "rb") as fh:
        req = urllib.request.Request(f"{bucket}/{name}?access_token={tok}",
                                     data=fh, method="PUT")
        req.add_header("Content-Type", "application/octet-stream")
        req.add_header("Content-Length", str(size))
        with urllib.request.urlopen(req, timeout=7200) as r:
            r.read()
    print(f"   done: {name}", flush=True)


def repair_dates(meta):
    """Zenodo returns `dates` entries it will not accept back.

    The Westney record carries `{"type": "available", "description": "v1.0 published on
    the fourMs Lab website the day after the 2010-02-18 recording"}` --- a date entry with
    a description and **no date**. Reading the record is happy with that; writing it back
    fails with "Invalid date provided". It is a real flaw in the deposited metadata, and
    the description says what the missing value is, so it is filled in rather than
    dropped: the day after 2010-02-18.
    """
    fixed = []
    for entry in meta.get("dates", []) or []:
        if not entry.get("start") and not entry.get("end"):
            if "2010-02-18" in (entry.get("description") or ""):
                entry = {**entry, "start": "2010-02-19"}
            else:
                continue          # no date and nothing to infer one from
        fixed.append(entry)
    if fixed:
        meta["dates"] = fixed
    else:
        meta.pop("dates", None)
    return meta


def fix_metadata(draft_id, tok, publish):
    """Set the version on an existing draft whose files are already uploaded."""
    draft = api("GET", f"https://zenodo.org/api/deposit/depositions/{draft_id}", tok)
    meta = repair_dates(draft["metadata"])
    meta["version"] = NEW_VERSION
    api("PUT", f"https://zenodo.org/api/deposit/depositions/{draft_id}", tok,
        {"metadata": meta})
    print(f"metadata version set to {NEW_VERSION}, dates repaired")
    if not publish:
        print(f"draft ready, NOT published: https://zenodo.org/deposit/{draft_id}")
        return 0
    out = api("POST", f"https://zenodo.org/api/deposit/depositions/{draft_id}/actions/"
              "publish", tok)
    print(f"published: {out.get('doi_url') or out.get('doi')}")
    return 0


def main():
    go, publish = "--go" in sys.argv, "--publish" in sys.argv
    if "--fix" in sys.argv:
        draft_id = int(sys.argv[sys.argv.index("--fix") + 1])
        return fix_metadata(draft_id, token(), publish)
    tok = token()
    for f in REPLACE + ADD:
        p = os.path.join(STAGE, f)
        if not os.path.exists(p):
            sys.exit(f"missing from the staging directory: {p}")

    print(f"record {RECORD}: replace {', '.join(REPLACE)}; add {', '.join(ADD)}")
    print(f"version -> {NEW_VERSION}")
    if not go:
        print("\ndry run. add --go to create the draft and upload, "
              "and --publish as well to publish it.")
        return 0

    d = api("POST", f"https://zenodo.org/api/deposit/depositions/{RECORD}/actions/"
            "newversion", tok)
    draft_url = d["links"]["latest_draft"]
    draft = api("GET", draft_url, tok)
    draft_id, bucket = draft["id"], draft["links"]["bucket"]
    print(f"draft {draft_id} created")

    for f in draft.get("files", []):
        if f["filename"] in REPLACE:
            api("DELETE", f"https://zenodo.org/api/deposit/depositions/{draft_id}/files/"
                f"{f['id']}", tok)
            print(f"   removed the old {f['filename']}")

    for f in REPLACE + ADD:
        put_file(bucket, f, os.path.join(STAGE, f), tok)

    meta = repair_dates(draft["metadata"])
    meta["version"] = NEW_VERSION
    api("PUT", f"https://zenodo.org/api/deposit/depositions/{draft_id}", tok,
        {"metadata": meta})
    print(f"metadata version set to {NEW_VERSION}")

    if not publish:
        print(f"\ndraft ready, NOT published: https://zenodo.org/deposit/{draft_id}")
        print("check it there, then re-run with --go --publish, or press publish on the "
              "page.")
        return 0

    out = api("POST", f"https://zenodo.org/api/deposit/depositions/{draft_id}/actions/"
              "publish", tok)
    print(f"\npublished: {out.get('doi_url') or out.get('doi')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
