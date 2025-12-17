# repo-tool

A CLI tool that generates an opam repository and monorepo from a list of git repositories.

## Overview

`repo-tool` reads a text file containing git repository URLs and:

1. Clones each repository into a `vendor/` directory
2. Generates an opam repository structure in `opam-repository/`
3. Creates a `setup.sh` script to pin packages and install dependencies
4. Sets up dune to build everything as a monorepo

This is useful for creating a local development environment with multiple interdependent packages that may not yet be published to opam.

## Installation

```bash
opam install . --deps-only
dune build
dune install
```

Or run directly:

```bash
dune exec repo-tool -- <args>
```

## Usage

```bash
repo-tool INPUT_FILE [-o OUTPUT_DIR] [-v]
```

### Arguments

- `INPUT_FILE` - Path to a text file containing git repository URLs (one per line)
- `-o, --output DIR` - Output directory (default: `opam-repository`)
- `-v, --verbose` - Enable verbose output

### Input File Format

```
# Comments start with #
https://github.com/user/repo1.git
https://github.com/user/repo2.git main
https://tangled.org/user/repo3
```

Each line contains a git URL, optionally followed by a branch name.

## Output Structure

```
output-dir/
├── dune-project           # Dune project file
├── dune                   # Top-level dune config
├── setup.sh               # Setup script for opam switch
├── opam-repository/
│   ├── repo               # opam repository metadata
│   └── packages/
│       └── <pkg>/
│           └── <pkg>.dev/
│               └── opam   # Package opam file with url stanza
└── vendor/
    ├── dune               # Lists vendor subdirectories
    ├── repo1/             # Cloned source code
    ├── repo2/
    └── ...
```

## Setting Up the Monorepo

After running `repo-tool`, set up the development environment:

```bash
cd output-dir
./setup.sh
```

The setup script will:
1. Create a local opam switch with OCaml 5.4.0
2. Pin all vendor packages
3. Install dependencies (including test dependencies)
4. Run `dune build`

Alternatively, run the steps manually:

```bash
cd output-dir
opam switch create . 5.4.0 -y
opam pin add -ny <pkg1> vendor/<repo1>
opam pin add -ny <pkg2> vendor/<repo2>
# ... for each package
opam install -y --deps-only --with-test <pkg1> <pkg2> ...
opam exec -- dune build --root .
```

## Using the opam Repository as an Overlay

You can also use just the generated opam repository as an overlay:

```bash
opam repository add local /path/to/output-dir/opam-repository
opam update
opam install <package-name>
```

## Incremental Updates

Running `repo-tool` again on an existing output directory will:
- Update existing repositories with `git pull`
- Clone any new repositories
- Regenerate the opam repository and setup script

## Example

```bash
# Create a repos.txt file
cat > repos.txt << EOF
https://github.com/user/ocaml-foo
https://github.com/user/ocaml-bar
https://tangled.org/user/ocaml-baz
EOF

# Generate the monorepo
repo-tool repos.txt -o my-monorepo -v

# Set up and build
cd my-monorepo
./setup.sh
```
