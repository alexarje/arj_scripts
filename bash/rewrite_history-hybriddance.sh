#!/bin/bash
# Remove the consent forms, agreements and media releases from every commit.
#
# Six PDFs under Documentation/Regulatory/, whose FILENAMES name the participants, so the
# paths have to go and not just the contents. They were untracked on 2026-08-26, which
# took them out of the index and left them in every earlier commit.
#
# This is irreversible, so: a full copy of .git is taken first, onto the internal disk
# rather than the Seagate, which has dropped off the USB bus mid-write before. And the
# check afterwards is that HEAD's TREE HASH IS UNCHANGED --- the rewrite must alter
# history and nothing about the current state of the work.
set -euo pipefail
R="/media/alexanje/Seagate Hub/aktiv/HybridDanceImprov"
FR="/tmp/claude-1000/-media-alexanje-Seagate-Hub-aktiv-HybridDanceImprov/4652fe30-e869-49e7-9f57-01a851da096d/scratchpad/frenv/bin/git-filter-repo"
BACKUP="$HOME/hybriddance-git-backup-$(date +%Y%m%d-%H%M%S)"
cd "$R"

if [ -n "$(git status --porcelain)" ]; then
  echo "REFUSING: the working tree is not clean. Commit first."
  git status --short
  exit 1
fi

BEFORE_TREE=$(git rev-parse HEAD^{tree})
BEFORE_COMMITS=$(git rev-list --all --count)
BEFORE_FILES=$(git ls-files | wc -l)
echo "before: $BEFORE_COMMITS commits, $BEFORE_FILES tracked files, tree $BEFORE_TREE"

echo "backing up .git to $BACKUP"
cp -a .git "$BACKUP"
du -sh "$BACKUP"

echo "rewriting..."
"$FR" --force --invert-paths --path "Documentation/Regulatory/"

AFTER_TREE=$(git rev-parse HEAD^{tree})
AFTER_COMMITS=$(git rev-list --all --count)
AFTER_FILES=$(git ls-files | wc -l)
echo "after:  $AFTER_COMMITS commits, $AFTER_FILES tracked files, tree $AFTER_TREE"

echo "--- verification ---"
LEFT=$(git log --all --pretty=format: --name-only | sort -u | grep -ci "Regulatory" || true)
echo "paths matching Regulatory anywhere in history: $LEFT  (must be 0)"
[ "$LEFT" = "0" ] || { echo "FAILED: still present"; exit 1; }
[ "$BEFORE_TREE" = "$AFTER_TREE" ] || { echo "FAILED: HEAD tree changed, the working state was altered"; exit 1; }
[ "$BEFORE_FILES" = "$AFTER_FILES" ] || { echo "FAILED: tracked file count changed"; exit 1; }
echo "HEAD tree unchanged and no Regulatory path survives"

git reflog expire --expire=now --all
git gc --prune=now --quiet
echo "objects pruned; backup kept at $BACKUP"
