# Workspace image assembler internals

`template/assemble.py` deliberately performs very little transformation. It
validates a profile, finds folders, preserves declaration order, concatenates
three kinds of text, and writes a standalone Docker build/Coder template
directory.

## Assembly flow

1. Read and strictly validate the JSON profile.
2. Resolve every `features.root` name to `modules/root/NAME` and every
   `features.userspace` name to `modules/userspace/NAME`.
3. Require each selected folder and its `Dockerfile` slice to exist. Feature
   names are not enumerated in Python or JSON Schema.
4. Copy the selected folders to generated `features/root/` and
   `features/userspace/` paths.
5. Paste root Dockerfile slices into `base/Dockerfile` in root-list order.
6. Paste userspace slices after `USER coder` in userspace-list order.
7. Concatenate optional feature `init` and `bash_config` fragments in the same
   root-then-userspace order.
8. Discover filenames directly below each selected `.local/bin` and write the
   interactive-shell script list.
9. Render profile environment, generated README, safety marker, and a
   source-hash lock file. Write all Terraform files under generated
   `terraform/`.
10. Replace an old marked output only after the new temporary output is
    complete.

The assembler has no third-party Python dependency and does not run Docker,
Terraform, shell installers, or package managers.

## Generated directory split

The generated root is the Docker build context. Terraform is isolated below a
single directory:

```text
generated-workspace/
├── Dockerfile
├── base/
├── features/
├── terraform/
│   ├── modules.tf
│   ├── profile.tf
│   └── template.tf
├── README.md
└── profile.lock.json
```

Run `docker build` from `generated-workspace/`, and point Coder at
`generated-workspace/terraform/`.

## Dockerfile phases

The base Dockerfile has four stable phases:

```text
base image, environment, locale and universal packages
  -> mandatory coder user and complete shell files
  -> ordered root feature slices
  -> USER coder and ordered userspace feature slices
  -> root apt-list cleanup, USER coder and CMD
```

Each ordinary package install belongs directly in its feature's Dockerfile:

```dockerfile
RUN apt-get update && \
    apt-get install -y --no-install-recommends package-one package-two
```

This intentionally creates more Docker layers. Editing a later feature does
not invalidate earlier package layers. Apt lists remain available until all
root features finish and are cleared once at the end.

The assembler adds only comment banners around a feature fragment. It does not
rewrite its commands. The exact source text can therefore be reviewed in
isolation or pasted into the final Dockerfile.

## Direct home paths

A feature directory mirrors only paths below `/home/coder`:

```text
modules/root/example/
├── Dockerfile
├── init
├── bash_config
├── .config/example/config
└── .local/bin/example-tool
```

Its Dockerfile owns the copy:

```dockerfile
COPY --chown=coder:coder ./features/root/example/.config/ /home/coder/.config/
COPY --chown=coder:coder ./features/root/example/.local/ /home/coder/.local/
RUN chmod 0755 /home/coder/.local/bin/example-tool
```

The generated context uses `features/...` because it contains only the selected
source folders. The checked-in reusable source uses `modules/...`. This is the
only path translation; there is no nested overlay tree.

Docker applies feature copy commands in profile order. That makes replacement
explicit and readable in the final Dockerfile. A later selected feature can
intentionally replace an earlier file, so profiles own composition order.

## One-time initialization

Every selected `init` fragment becomes one annotated section of generated
`base/init`. On Coder agent startup, `workspace-init`:

1. creates the small set of expected XDG/runtime directories;
2. runs `$HOME/.config/workspace/init` when it exists;
3. renames it to `$HOME/.config/workspace/init.done` only after success.

There are no numbered hooks, checksums, `/etc/skel` copies, loader insertion, or
per-feature dispatcher directories. A failed init remains named `init` and is
retried on the next workspace start. A successful init does not run again.

Because `/home` is a persistent Docker volume, an existing workspace keeps its
current files when an image is rebuilt. To apply a new image seed, create a new
volume or perform an explicit user-data migration.

## Bash composition

`base/.bashrc` and `base/.profile` are complete files copied during image build.
They establish the home/XDG/PATH environment without relying on
Debian's `/etc/skel`.

After the mandatory environment and generated desktop/profile environment,
`.bashrc` sources:

```bash
. "$HOME/.config/bash_config"
```

The generated `bash_config` is the ordered concatenation of selected feature
fragments. Use a fragment only for lightweight exports, aliases, functions and
prompt initialization. Do not put package installation or long-running startup
work there.

The shell reads `~/.config/workspace/scripts`, which the assembler derives from
selected `.local/bin` directories, and prints the workspace description plus a
colored list of commands. It also uses Bash's `declare -F` after loading the
assembled feature configuration to show the names of available shell functions.

## Add a root feature

1. Create `modules/root/NAME/Dockerfile`.
2. Add direct `.config`, `.local`, `.vscode` or other home paths only when the
   feature needs them.
3. Add optional `init` and/or `bash_config` fragments.
4. Add `NAME` to a profile's `features.root` at the exact desired position.
5. Run `assemble.py --check`, generate a temporary output, and run the tests.

No Python constant or schema enum changes are required.

## Add a userspace feature

Follow the same steps below `modules/userspace/NAME`. Its Dockerfile is inserted
after `USER coder`, so it must not require root privileges unless it explicitly
uses the already-configured passwordless `sudo`. Keep the feature in the
userspace list so its ownership and build phase remain obvious.

## Profile validation

The Python validator and `profile.schema.json` enforce shape, types, safe names,
display/GPU constraints, port ranges, preview settings and supported Coder
Registry modules. Feature values use a string pattern rather than an enum;
`feature_paths()` is the authoritative existence check.

The profile's display object still drives Terraform container resources and
runtime environment. Feature selection is explicit rather than inferred, so a
profile author must select the matching display folders and their dependencies
in the desired order.

Playwright keeps a small profile setting because its literal Dockerfile slice
needs a reference version when resolving Chromium operating-system libraries.
The assembler exports that version to the generated profile environment before
the feature layer runs.

An optional `preview` object controls the generated owner-only Preview app:

```json
{
  "preview": {
    "enabled": true,
    "port": 3000
  }
}
```

When enabled, the assembler also exports `WORKSPACE_PREVIEW_PORT`. It does not
start a server or infer a framework. Profiles without the object have no named
Preview app.

GPU profiles store only the render-node path. The owning numeric group varies
by Docker host, so generated Terraform asks for it as a required immutable
Coder parameter instead of accepting a profile default.

The optional `repository_url` is a workspace parameter implemented in the base
Terraform rather than profile JSON. This keeps repository identity outside the
reusable image profile. The official Git-clone module is pinned in
`base/terraform/modules.tf`.

## Output safety and reproducibility

Generation takes place in a temporary sibling directory. An existing output is
replaced only with `--force` and only if `.workspace-image-generated` exists.
The assembler refuses to write inside `template`.

`profile.lock.json` records ordered root/userspace feature names, discovered
scripts and SHA-256 hashes for the assembler, schema, profile, base and selected
feature files. It does not pin floating Debian images, apt packages, remote
install scripts, Homebrew, Starship or Coder
Registry downloads, Bun, uv, Homebrew or Starship installers.
