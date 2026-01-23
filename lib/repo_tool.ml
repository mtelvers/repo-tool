type repo_entry = {
  url : string;
  branch : string option;
}

let verbose = ref false

let log fmt =
  if !verbose then Printf.eprintf (fmt ^^ "\n%!")
  else Printf.ifprintf stderr fmt

let parse_repo_line line =
  let line = String.trim line in
  if String.length line = 0 || line.[0] = '#' then None
  else
    match String.split_on_char ' ' line with
    | [] -> None
    | [ url ] -> Some { url; branch = None }
    | url :: branch :: _ -> Some { url; branch = Some branch }

let read_lines filename =
  let ic = open_in filename in
  let rec loop acc =
    match input_line ic with
    | line -> loop (line :: acc)
    | exception End_of_file ->
        close_in ic;
        List.rev acc
  in
  loop []

let read_repo_file path =
  let lines = read_lines path in
  List.filter_map parse_repo_line lines

let extract_repo_name url =
  let url = String.trim url in
  let url =
    if String.ends_with ~suffix:".git" url then
      String.sub url 0 (String.length url - 4)
    else url
  in
  (* Remove trailing slash if present *)
  let url =
    if String.ends_with ~suffix:"/" url then
      String.sub url 0 (String.length url - 1)
    else url
  in
  match String.split_on_char '/' url |> List.rev with
  | name :: _ -> name
  | [] -> "unknown"

let run_command cmd =
  let exit_code = Sys.command cmd in
  if exit_code = 0 then Ok ()
  else Error (Printf.sprintf "Command failed with exit code %d: %s" exit_code cmd)

let get_git_sha repo_path =
  let cmd = Printf.sprintf "git -C %s rev-parse HEAD" repo_path in
  let ic = Unix.open_process_in cmd in
  let sha = input_line ic in
  ignore (Unix.close_process_in ic);
  String.trim sha

let rec mkdir_p path =
  if Sys.file_exists path then ()
  else begin
    mkdir_p (Filename.dirname path);
    Unix.mkdir path 0o755
  end

let clone_or_update_repo ~vendor_dir entry =
  let name = extract_repo_name entry.url in
  let target = Filename.concat vendor_dir name in
  if Sys.file_exists target then begin
    log "Updating %s in %s" entry.url target;
    let cmd = Printf.sprintf "git -C %s pull --ff-only 2>/dev/null" target in
    match run_command cmd with
    | Ok () -> Ok target
    | Error _ ->
        (* If pull fails, try a fresh clone *)
        log "Pull failed, re-cloning %s" entry.url;
        let rm_cmd = Printf.sprintf "rm -rf %s" target in
        ignore (run_command rm_cmd);
        let branch_args =
          match entry.branch with
          | Some b -> Printf.sprintf "--branch %s" b
          | None -> ""
        in
        let clone_cmd =
          Printf.sprintf "git clone --depth 1 %s %s %s 2>/dev/null"
            branch_args entry.url target
        in
        match run_command clone_cmd with
        | Ok () -> Ok target
        | Error msg ->
            Printf.eprintf "Failed to clone %s: %s\n%!" entry.url msg;
            Error msg
  end
  else begin
    log "Cloning %s to %s" entry.url target;
    let branch_args =
      match entry.branch with
      | Some b -> Printf.sprintf "--branch %s" b
      | None -> ""
    in
    let cmd =
      Printf.sprintf "git clone --depth 1 %s %s %s 2>/dev/null"
        branch_args entry.url target
    in
    match run_command cmd with
    | Ok () -> Ok target
    | Error msg ->
        Printf.eprintf "Failed to clone %s: %s\n%!" entry.url msg;
        Error msg
  end

let find_opam_files repo_path =
  let files = Sys.readdir repo_path in
  Array.to_list files
  |> List.filter (fun f -> String.ends_with ~suffix:".opam" f)
  |> List.map (fun f -> Filename.concat repo_path f)

let read_file path =
  let ic = open_in path in
  let n = in_channel_length ic in
  let content = really_input_string ic n in
  close_in ic;
  content

let write_file path content =
  let oc = open_out path in
  output_string oc content;
  close_out oc

let extract_version_from_opam content =
  let lines = String.split_on_char '\n' content in
  let version_line =
    List.find_opt
      (fun line ->
        let trimmed = String.trim line in
        String.length trimmed > 8 && String.sub trimmed 0 8 = "version:")
      lines
  in
  match version_line with
  | Some line -> (
      let parts = String.split_on_char '"' line in
      match parts with _ :: ver :: _ -> Some ver | _ -> None)
  | None -> None

let package_name_from_opam_path path =
  let basename = Filename.basename path in
  if String.ends_with ~suffix:".opam" basename then
    String.sub basename 0 (String.length basename - 5)
  else basename

let generate_repo_structure ~output_dir ~repo_path ~git_url ~git_sha =
  let opam_files = find_opam_files repo_path in
  let packages_dir = Filename.concat output_dir "packages" in
  mkdir_p packages_dir;
  List.iter
    (fun opam_path ->
      let pkg_name = package_name_from_opam_path opam_path in
      let content = read_file opam_path in
      let version =
        match extract_version_from_opam content with
        | Some v -> v
        | None -> "dev"
      in
      let pkg_dir =
        Filename.concat packages_dir
          (Filename.concat pkg_name (pkg_name ^ "." ^ version))
      in
      log "Creating package %s.%s" pkg_name version;
      mkdir_p pkg_dir;
      let opam_target = Filename.concat pkg_dir "opam" in
      let url_section =
        Printf.sprintf "\nurl {\n  src: \"git+%s#%s\"\n}\n" git_url git_sha
      in
      let lines = String.split_on_char '\n' content in
      let filtered =
        List.filter
          (fun line ->
            let trimmed = String.trim line in
            not
              (String.length trimmed > 8
              && String.sub trimmed 0 8 = "version:"))
          lines
      in
      let final_content = String.concat "\n" filtered ^ url_section in
      write_file opam_target final_content)
    opam_files

let create_repo_file output_dir =
  let repo_path = Filename.concat output_dir "repo" in
  write_file repo_path "opam-version: \"2.0\"\n"

let collect_all_packages vendor_dirs =
  List.concat_map
    (fun vendor_path ->
      let opam_files = find_opam_files vendor_path in
      List.map
        (fun opam_path ->
          let pkg_name = package_name_from_opam_path opam_path in
          (pkg_name, vendor_path))
        opam_files)
    vendor_dirs

let create_setup_script output_dir packages =
  let script_path = Filename.concat output_dir "setup.sh" in
  let buf = Buffer.create 1024 in
  Buffer.add_string buf "#!/bin/sh\n";
  Buffer.add_string buf "# Auto-generated setup script for monorepo\n\n";
  Buffer.add_string buf "set -e\n\n";
  Buffer.add_string buf "echo \"Creating opam switch...\"\n";
  Buffer.add_string buf "opam switch create . 5.4.0 -y\n\n";
  Buffer.add_string buf "echo \"Pinning vendor packages...\"\n";
  List.iter
    (fun (pkg_name, vendor_path) ->
      let rel_path = "vendor/" ^ Filename.basename vendor_path in
      Buffer.add_string buf
        (Printf.sprintf "opam pin add -ny %s %s\n" pkg_name rel_path))
    packages;
  Buffer.add_string buf "\necho \"Installing dependencies...\"\n";
  let pkg_names = List.map fst packages |> String.concat " " in
  Buffer.add_string buf (Printf.sprintf "opam install -y --deps-only --with-test %s\n" pkg_names);
  Buffer.add_string buf "\necho \"Building...\"\n";
  Buffer.add_string buf "opam exec -- dune build --root .\n";
  Buffer.add_string buf "\necho \"Done!\"\n";
  write_file script_path (Buffer.contents buf);
  Unix.chmod script_path 0o755

let create_dune_project output_dir vendor_dirs =
  let dune_project_path = Filename.concat output_dir "dune-project" in
  let content = "(lang dune 3.0)\n" in
  write_file dune_project_path content;
  (* Create top-level dune file *)
  let dune_path = Filename.concat output_dir "dune" in
  let dune_content = "(dirs vendor opam-repository)\n" in
  write_file dune_path dune_content;
  (* Create vendor dune file that lists subdirs *)
  let vendor_dir = Filename.concat output_dir "vendor" in
  let vendor_dune_path = Filename.concat vendor_dir "dune" in
  let subdirs =
    List.map (fun d -> Filename.basename d) vendor_dirs
    |> String.concat " "
  in
  let vendor_dune_content = Printf.sprintf "(dirs %s)\n" subdirs in
  write_file vendor_dune_path vendor_dune_content;
  (* Create setup script *)
  let packages = collect_all_packages vendor_dirs in
  create_setup_script output_dir packages

let run ~input_file ~output_dir ~verbose:v =
  verbose := v;
  Printf.printf "Reading repository list from %s\n%!" input_file;
  let entries = read_repo_file input_file in
  Printf.printf "Found %d repositories to process\n%!" (List.length entries);
  mkdir_p output_dir;
  let opam_repo_dir = Filename.concat output_dir "opam-mono-repo" in
  mkdir_p opam_repo_dir;
  create_repo_file opam_repo_dir;
  let vendor_dir = Filename.concat output_dir "vendor" in
  mkdir_p vendor_dir;
  log "Using vendor directory %s" vendor_dir;
  let results =
    List.map
      (fun entry ->
        match clone_or_update_repo ~vendor_dir entry with
        | Ok repo_path ->
            let git_sha = get_git_sha repo_path in
            generate_repo_structure ~output_dir:opam_repo_dir ~repo_path ~git_url:entry.url ~git_sha;
            Ok repo_path
        | Error msg -> Error msg)
      entries
  in
  let vendor_dirs =
    List.filter_map (function Ok p -> Some p | Error _ -> None) results
  in
  let errors =
    List.filter_map (function Error e -> Some e | Ok _ -> None) results
  in
  create_dune_project output_dir vendor_dirs;
  if List.length errors > 0 then begin
    Printf.eprintf "Completed with %d errors:\n%!" (List.length errors);
    List.iter (fun e -> Printf.eprintf "  - %s\n%!" e) errors
  end;
  Printf.printf "Output written to %s\n%!" output_dir;
  Printf.printf "  opam-repository/ - opam package definitions\n%!";
  Printf.printf "  vendor/          - source code\n%!";
  Printf.printf "  setup.sh         - run to pin packages and install deps\n%!";
  if List.length errors > 0 then 1 else 0
