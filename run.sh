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
    git clone https://github.com/tunbury/claude-repo "$OPAM_REPO_DIR"
else
    git -C "$OPAM_REPO_DIR" remote set-url origin https://github.com/tunbury/claude-repo 2>/dev/null || \
        git -C "$OPAM_REPO_DIR" remote add origin https://github.com/tunbury/claude-repo
fi

restore_vendor_git() {
    find "$VENDOR_DIR" -mindepth 2 -maxdepth 2 -name ".git.bak" -type d 2>/dev/null | while read dir; do
        mv "$dir" "$(dirname "$dir")/.git"
    done
}

hide_vendor_git() {
    find "$VENDOR_DIR" -mindepth 2 -maxdepth 2 -name ".git" -type d 2>/dev/null | while read dir; do
        mv "$dir" "$(dirname "$dir")/.git.bak"
    done
    echo ".git.bak/" > "$VENDOR_DIR/.gitignore"
}

# Restore .git directories for pulling and running the tool
restore_vendor_git

# Ensure .git directories are hidden again even if the script fails
trap hide_vendor_git EXIT

# Run the tool
opam exec -- dune exec -- repo-tool repos.txt

# Hide .git directories before the commit steps (trap will be a no-op)
hide_vendor_git

# Commit and push changes to vendor repo
cd "$VENDOR_DIR"
if [ -n "$(git status --porcelain)" ]; then
    git add -A
    git commit -m "$(git status --porcelain)"
    git push
fi
cd - > /dev/null

# Update README.md with package table
README="$OPAM_REPO_DIR/README.md"
if [ -f "$README" ]; then
    # Generate package table
    TABLE="| Package | Description |\n|---------|-------------|"
    for opam in "$OPAM_REPO_DIR"/packages/*/*/opam; do
        if [ -f "$opam" ]; then
            pkg=$(basename "$(dirname "$opam")")
            synopsis=$(grep -m1 '^synopsis:' "$opam" | sed 's/^synopsis: *"\(.*\)"$/\1/')
            TABLE="$TABLE\n| \`$pkg\` | $synopsis |"
        fi
    done

    # Replace table in README (between ## Packages and next ##)
    awk -v table="$TABLE" '
        /^## Packages/ { print; getline; print; printing=0; printf table "\n"; next }
        /^## / && printing==0 { printing=1 }
        printing { print }
        !printing && !/^\|/ { print }
    ' "$README" > "$README.tmp" && mv "$README.tmp" "$README"
fi

# Commit and push changes to opam-repository
cd "$OPAM_REPO_DIR"
if [ -n "$(git status --porcelain)" ]; then
    git add -A
    git commit -m "$(git status --porcelain)"
    git push
fi
cd - > /dev/null
