#!/usr/bin/env python3
"""Re-create a GitHub release so Zenodo archives it, without changing the code.

    python3 ~/zrel.py micromotion            # dry run: shows what it would do
    python3 ~/zrel.py micromotion --go       # does it

Zenodo's GitHub integration archives only releases PUBLISHED AFTER the integration is switched on.
It does not backfill. All four toolboxes were released before it was enabled, so none is archived
and none has a DOI. Deleting the release object and re-creating it against the SAME TAG makes
GitHub emit `release: published` again, which is what Zenodo listens for.

What this does NOT do: touch the tag, the code, or the version. The commit Zenodo archives is
exactly the one already released.

Expect the PyPI workflow to FAIL on the re-release, and that is correct rather than a problem: it
fires on `release: [published]` too, and PyPI refuses a version it already has. Checked before
writing this — micromotion 1.12.0, ambiscape 0.42.0, musiscape 0.5.0 and musicalgestures 1.11.1 are
all already on PyPI. A red cross on that run means the guard worked.

The release notes are read back from GitHub and written to a file first, so nothing is lost if the
re-create fails. If it does fail, the notes are still on disk and the tag is untouched, so
`gh release create <tag> --notes-file <file>` finishes the job by hand.
"""
import json
import os
import subprocess
import sys

REPOS = {
    "micromotion":     "~/github/micromotion",
    "ambiscape":       "~/github/ambiscape",
    "musiscape":       "~/github/musiscape",
    "musicalgestures": "~/github/MGT-python",
}


def sh(cmd, cwd, check=True):
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if check and r.returncode != 0:
        sys.exit(f"FAILED: {' '.join(cmd)}\n{r.stdout}\n{r.stderr}")
    return r.stdout.strip(), r.returncode


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in REPOS:
        sys.exit(f"give one of: {', '.join(REPOS)}\n\n{__doc__}")
    name = sys.argv[1]
    go = "--go" in sys.argv
    cwd = os.path.expanduser(REPOS[name])

    tag, _ = sh(["git", "describe", "--tags", "--abbrev=0"], cwd)
    out, _ = sh(["gh", "release", "view", tag, "--json", "tagName,name,body,isDraft,isPrerelease"], cwd)
    rel = json.loads(out)
    body = rel["body"]
    if not body.strip():
        sys.exit(f"{name}: the release has empty notes; refusing, since re-creating would lose nothing but would look like it did")
    if rel["isDraft"] or rel["isPrerelease"]:
        sys.exit(f"{name}: release is draft/prerelease; handle by hand")

    notes = os.path.expanduser(f"~/zrel-{name}-{tag}-notes.md")
    with open(notes, "w") as fh:
        fh.write(body)

    print(f"repo   : {name}  ({cwd})")
    print(f"tag    : {tag}   (NOT touched)")
    print(f"title  : {rel['name']}")
    print(f"notes  : {len(body)} chars saved to {notes}")
    if not go:
        print("\nDRY RUN. Re-run with --go to delete and re-create the release object.")
        print("Expect the PyPI job to fail on a duplicate version; that is the intended outcome.")
        return

    print("\ndeleting the release object …")
    sh(["gh", "release", "delete", tag, "--yes"], cwd)
    print("re-creating it against the same tag …")
    sh(["gh", "release", "create", tag, "--title", rel["name"], "--notes-file", notes], cwd)
    url, _ = sh(["gh", "release", "view", tag, "--json", "url", "-q", ".url"], cwd)
    print(f"done: {url}")
    print("\nZenodo should archive it within a minute or two. Check https://zenodo.org/account/settings/github/")
    print("The notes file is kept, in case anything needs re-posting.")


if __name__ == "__main__":
    main()
