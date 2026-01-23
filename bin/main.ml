open Cmdliner

let input_file =
  let doc = "Path to the input file containing git repository URLs (one per line)." in
  Arg.(required & pos 0 (some file) None & info [] ~docv:"INPUT_FILE" ~doc)

let output_dir =
  let doc = "Output directory for the generated opam repository." in
  Arg.(value & opt string "opam-mono-repo" & info [ "o"; "output" ] ~docv:"DIR" ~doc)

let verbose =
  let doc = "Enable verbose output." in
  Arg.(value & flag & info [ "v"; "verbose" ] ~doc)

let run input_file output_dir verbose =
  let exit_code = Repo_tool.run ~input_file ~output_dir ~verbose in
  exit exit_code

let run_t = Term.(const run $ input_file $ output_dir $ verbose)

let cmd =
  let doc = "Generate an opam repository from git repositories" in
  let man =
    [
      `S Manpage.s_description;
      `P
        "$(tname) reads a text file containing a list of git repository URLs \
         and generates an opam repository structure. Each line in the input \
         file should contain a git URL, optionally followed by a branch name.";
      `S Manpage.s_examples;
      `P "Create an opam repository from repos.txt:";
      `Pre "  $(tname) repos.txt -o my-opam-repo";
      `P "Input file format:";
      `Pre
        "  https://github.com/user/repo1.git\n\
        \  https://github.com/user/repo2.git main\n\
        \  # This is a comment";
      `S Manpage.s_bugs;
      `P "Report bugs at https://github.com/mtelvers/repo-tool/issues";
    ]
  in
  let info = Cmd.info "repo-tool" ~version:"0.1.0" ~doc ~man in
  Cmd.v info run_t

let () = exit (Cmd.eval cmd)
