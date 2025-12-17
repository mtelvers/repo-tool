(lang dune 3.0)

(name repo_tool)

(generate_opam_files true)

(source
 (github mtelvers/repo-tool))

(authors "Mark Elvers")

(maintainers "Mark Elvers")

(license MIT)

(package
 (name repo_tool)
 (synopsis "Generate opam repository from git repositories")
 (description
  "A CLI tool that reads a text file containing git repository URLs and generates an opam repository structure that can be overlaid on the official opam repository.")
 (depends
  (ocaml (>= 4.14))
  dune
  cmdliner))
