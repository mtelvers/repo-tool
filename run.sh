#!/bin/sh
set -e

VENDOR_DIR="opam-mono-repo/vendor"
OPAM_REPO_DIR="opam-mono-repo/opam-repository"

# Ensure directory structure exists
mkdir -p "$(dirname "$VENDOR_DIR")"
mkdir -p "$(dirname "$OPAM_REPO_DIR")"

# Set up git repos before running the tool
if [ ! -d "$VENDOR_DIR/.git" ]; then
    rm -rf "$VENDOR_DIR"
    git clone git@git.recoil.org:mtelvers.tunbury.org/claude-mono "$VENDOR_DIR"
else
    git -C "$VENDOR_DIR" remote set-url origin git@git.recoil.org:mtelvers.tunbury.org/claude-mono 2>/dev/null || \
        git -C "$VENDOR_DIR" remote add origin git@git.recoil.org:mtelvers.tunbury.org/claude-mono
fi

if [ ! -d "$OPAM_REPO_DIR/.git" ]; then
    rm -rf "$OPAM_REPO_DIR"
    git clone https://github.com/mtelvers/claude-repo "$OPAM_REPO_DIR"
else
    git -C "$OPAM_REPO_DIR" remote set-url origin https://github.com/mtelvers/claude-repo 2>/dev/null || \
        git -C "$OPAM_REPO_DIR" remote add origin https://github.com/mtelvers/claude-repo
fi

# Restore .git directories for pulling
find "$VENDOR_DIR" -mindepth 2 -maxdepth 2 -name ".git.bak" -type d 2>/dev/null | while read dir; do
    mv "$dir" "$(dirname "$dir")/.git"
done

# Run the tool
opam exec -- dune exec -- repo-tool repos.txt

# Hide .git directories so they don't appear as submodules
find "$VENDOR_DIR" -mindepth 2 -maxdepth 2 -name ".git" -type d 2>/dev/null | while read dir; do
    mv "$dir" "$(dirname "$dir")/.git.bak"
done

# Ensure .git.bak directories are ignored
echo ".git.bak/" > "$VENDOR_DIR/.gitignore"

# Commit and push changes to vendor repo
cd "$VENDOR_DIR"
if [ -n "$(git status --porcelain)" ]; then
    git add -A
    git commit -m "$(git status --porcelain)"
    git push
fi
cd - > /dev/null

# Commit and push changes to opam-mono-repo
cd "$OPAM_REPO_DIR"
if [ -n "$(git status --porcelain)" ]; then
    git add -A
    git commit -m "$(git status --porcelain)"
    git push
fi
cd - > /dev/null
