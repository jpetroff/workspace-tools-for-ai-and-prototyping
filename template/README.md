# Workspace template assembler

This directory turns a small JSON profile into a standalone Docker build
context and Coder Terraform template. Profiles select ordered root and
userspace features; the assembler copies their source and inserts their literal
Dockerfile fragments without running installers or provisioning infrastructure.

## Profiles

The public defaults are:

- `profiles/base.json` — browser IDE and command-line tools;
- `profiles/web-prototype.json` — live preview, Playwright and X11 desktop;
- `profiles/desktop-app.json` — Tauri and software-rendered Wayland.

AMD render-node variants are under `profiles/advanced/`. They require the host
render-node GID when a workspace is created.

## Validate and generate

From the repository root:

```bash
python3 template/assemble.py \
  --profile template/profiles/web-prototype.json \
  --check

python3 template/assemble.py \
  --profile template/profiles/web-prototype.json \
  --output generated/web-prototype
```

An existing output can be replaced with `--force` only when it contains the
assembler's `.workspace-image-generated` safety marker.

The generated directory is both a Docker build context and a Coder template:

```text
generated/web-prototype/
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

Build from the generated root and push Terraform from its subdirectory:

```bash
docker build -t coder-ai-web-prototype:latest generated/web-prototype
coder templates push coder-ai-web-prototype \
  --directory generated/web-prototype/terraform
```

## Feature contract

Each `modules/root/NAME` or `modules/userspace/NAME` directory must contain a
`Dockerfile`. It may also contain:

- `init` for one-time workspace initialization;
- `bash_config` for lightweight shell configuration;
- direct `.config/`, `.local/`, or `.vscode/` trees copied by its Dockerfile.

Feature order is intentional. Root features run first as root, followed by
userspace features as `coder`; init and shell fragments follow the same order.
Feature names are discovered from folders instead of being enumerated in the
schema.

See [EXTENDING.md](EXTENDING.md) for the complete profile and extension
contract. See the repository [setup guide](../setup.md) for deployment.

## Tests

```bash
PYTHONDONTWRITEBYTECODE=1 \
  python3 -m unittest discover -s template/tests -v
```
