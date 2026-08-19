# Coder AI Workspaces setup guide

This guide is for the developer or administrator who builds and publishes the
workspace templates. Workspace users should normally only choose a template,
optionally enter a repository URL, and open its apps.

The supported baseline is a self-hosted Coder deployment whose provisioner can
manage a Docker host. Kubernetes and public-cloud resource templates are not
included.

## Architecture

Each generated profile produces two related artifacts:

1. A Docker build context containing Debian, common development tools, and the
   selected image features.
2. A Terraform directory that creates a Coder agent, persistent home volume,
   Docker container, browser IDE, optional repository clone, and profile apps.

The image contains no project-specific dependencies or AI-provider credentials.
Each repository owns its packages and browser revision. Coder supplies user
identity, generated SSH access, app routing, workspace lifecycle, and optional
secret injection.

## Prerequisites

Prepare a Linux computer or VM with:

- a running Docker daemon;
- a reachable Coder deployment and provisioner with Docker socket access;
- the Coder CLI logged into that deployment;
- Python 3.10 or newer for the dependency-free assembler;
- enough disk space to build the selected images.

Docker Desktop-compatible engines can work for a proof of concept, but the
advanced AMD profiles require a Linux Docker host with a DRM render node.

Follow Coder's current [Docker installation guide](https://coder.com/docs/install/docker)
when deploying the control plane. The Coder access URL must be reachable from
workspace containers; `localhost` is not a valid external access URL.

### Wildcard application domain

The Preview and Workspace Desktop apps use isolated subdomains and are private
to the workspace owner. Configure Coder's wildcard access URL and matching DNS
and TLS before publishing these profiles, for example:

```text
CODER_ACCESS_URL=https://coder.example.com
CODER_WILDCARD_ACCESS_URL=*.apps.coder.example.com
```

Use values appropriate for the deployment. See Coder's
[workspace application documentation](https://coder.com/docs/user-guides/workspace-access/web-ides)
and [port-forwarding guide](https://coder.com/docs/user-guides/workspace-access/port-forwarding).

## Choose a profile

| Profile file | Intended use | Host requirement |
| --- | --- | --- |
| `template/profiles/base.json` | CLI, services, code review | Ordinary Docker host |
| `template/profiles/web-prototype.json` | Web prototypes and browser testing | Ordinary Docker host |
| `template/profiles/desktop-app.json` | Tauri desktop prototypes | Ordinary Docker host |
| `template/profiles/advanced/web-prototype-amd-gpu.json` | GPU browser desktop | AMD DRM render node |
| `template/profiles/advanced/desktop-app-amd-gpu.json` | GPU Tauri desktop | AMD DRM render node |

The software-rendered profiles are the public defaults. Start with Web
Prototype for PM and designer workflows.

## Validate a profile

Run from the repository root:

```bash
python3 template/assemble.py \
  --profile template/profiles/web-prototype.json \
  --check
```

The check validates profile shape, feature names, feature folders, desktop
settings, ports, preview configuration, and Playwright settings. It does not
run Docker, Terraform, or package installers.

## Generate a build context

Keep generated output outside `template/`:

```bash
python3 template/assemble.py \
  --profile template/profiles/web-prototype.json \
  --output generated/web-prototype
```

To intentionally replace a previously generated directory:

```bash
python3 template/assemble.py \
  --profile template/profiles/web-prototype.json \
  --output generated/web-prototype \
  --force
```

`--force` only replaces a directory containing
`.workspace-image-generated`. The assembler refuses to replace an arbitrary
directory or write inside its source tree.

The output contains a `profile.lock.json` with source hashes. It records the
inputs used by the assembler, but it does not pin the contents of remote apt or
installer endpoints.

## Build the image

The profile's `image` value must match the tag built on the Docker host visible
to the Coder provisioner:

```bash
docker build \
  -t coder-ai-web-prototype:latest \
  generated/web-prototype
```

If Coder provisions on another host, push the image to an accessible registry
and update the profile image value before assembly, or provide the generated
template's `workspace_image` variable through the provisioner. Registry
authentication is an administrator responsibility.

## Publish the Coder template

Authenticate the CLI and upload only the generated Terraform directory:

```bash
coder login https://coder.example.com

coder templates push coder-ai-web-prototype \
  --directory generated/web-prototype/terraform
```

The template assumes the image already exists. Publishing Terraform does not
build or push the Docker image.

Create a smoke-test workspace from the dashboard or CLI:

```bash
coder create prototype-smoke-test \
  --template coder-ai-web-prototype
```

Leave **Git repository** blank for the empty-project path. For a clone test,
enter an HTTPS or SSH Git URL when creating a new workspace. The parameter is
immutable so changing projects means creating another isolated workspace.

## Repository cloning and Git authentication

The pinned official Git-clone module copies a supplied repository into
`/home/coder/projects`. code-server opens that clone. With no URL, code-server
opens `/home/coder/project`.

The template does not install dependencies or execute repository code. After
cloning, follow the repository's own README or let the AI assistant inspect its
lockfiles and documented setup.

### Generated SSH keys

Coder generates an SSH key pair for each user and makes it available to Git
without writing the private key into the workspace. Users can copy their public
key from Coder account settings and register it with their Git provider. Then
use an SSH URL such as:

```text
git@github.com:organization/project.git
```

Administrators can configure [Coder external auth](https://coder.com/docs/admin/external-auth)
for supported Git providers instead. Do not put access tokens in the repository
URL or profile JSON.

## Secrets

Template parameters are visible and must never carry API keys, tokens, or
passwords. Use organization secret management or Coder user secrets. For
example, on a deployment that supports user secrets:

```bash
printf %s "$PROTOTYPE_API_KEY" | \
  coder secret create prototype-api-key \
    --env PROTOTYPE_API_KEY \
    --description "API key for prototype workspaces"
```

Restart the workspace after creating or changing a secret. Anyone with shell
access to a workspace can read secrets injected into it, so do not share a
workspace containing credentials with an untrusted user. See
[Coder user secrets](https://coder.com/docs/user-guides/user-secrets).

## Preview workflow

Web profiles export:

```bash
WORKSPACE_PREVIEW_PORT=3000
```

Configure the development server to listen on that port. Examples:

```bash
# Vite-style projects
bun run dev -- --port "$WORKSPACE_PREVIEW_PORT"

# A simple static directory
python3 -m http.server "$WORKSPACE_PREVIEW_PORT"
```

Open **Preview** from the workspace dashboard. The app is owner-only. Coder also
shows other listening ports if the project must use a different port; the named
Preview app remains fixed at the profile's configured value.

Do not change Preview to public sharing without reviewing the prototype's data,
secrets, authentication, abuse risk, and expected lifetime.

## Workspace desktop

Web Prototype uses Xvfb, Openbox, x11vnc, and noVNC. Desktop App uses headless
Sway, WayVNC, and noVNC. The workspace starts the selected desktop through a
blocking Coder startup script when `display.autostart` is true.

Useful commands inside the workspace are:

```bash
workspace-desktop status
workspace-desktop health
workspace-desktop stop
workspace-desktop start
workspace-desktop restart
workspace-desktop env
```

Desktop processes run as `coder`. VNC and noVNC bind to workspace loopback and
are exposed only through the owner-only Workspace Desktop app. A virtual screen
has a fixed size; change `display.screen_size` in the profile and rebuild the
image/template to change the default.

### X11 versus Wayland

The Web Prototype profile uses X11 because it is lightweight and reliable for
headed Chromium. Xvfb supplies the display server; Openbox supplies window
focus, resize, and decoration behavior.

Desktop App uses Wayland because Tauri and GTK applications can run inside the
same headless Sway session. `wayland-software` uses llvmpipe, while
`wayland-gpu` exposes one explicitly selected AMD render node.

## Playwright

The Playwright feature installs Python and Chromium's Debian system libraries,
but intentionally omits a global Playwright package and browser binary. Each
repository must own matching versions.

Example Python setup:

```bash
cd ~/project
python3 -m venv .venv
source .venv/bin/activate
pip install playwright
playwright install chromium
```

If the repository uses uv:

```bash
uv sync
uv run playwright install chromium
```

Run the virtual desktop and open a persistent headed browser:

```bash
workspace-desktop start
playwright-browser --url http://127.0.0.1:3000
```

The browser helper can expose a loopback Chrome DevTools Protocol port for
another trusted process in the same workspace. Do not publish a CDP port as a
Coder app: it grants browser control.

When Playwright is upgraded in a project, reinstall the matching browser
revision. The profile's `playwright.deps_version` only selects a reference
version used to install compatible Debian libraries into the image.

## Tauri desktop applications

Desktop App profiles include Tauri v2's Linux dependencies, GTK, WebKitGTK,
GStreamer, OpenSSL headers, native compilers, GDB, LLDB, and VS Code task/launch
defaults. Rust itself can be installed by the project or through Linuxbrew.

Typical repository commands remain project-specific, for example:

```bash
bun install
bun run tauri dev
```

Open **Workspace Desktop** to interact with the application. Native debugging
profiles add `SYS_PTRACE`; this is intentionally absent from Base and Web
Prototype.

## AMD GPU profiles

On the Linux Docker host, find the render device and numeric owning group:

```bash
ls -l /dev/dri/renderD*
stat -c '%g' /dev/dri/renderD128
```

Advanced profiles default to the common render-node path
`/dev/dri/renderD128`, but they do not assume a group ID. Coder prompts for the
numeric **GPU render group GID** when the workspace is created. Enter the value
reported by the host.

The template maps only the selected render node and supplemental group. It does
not run the workspace as privileged or expose `/dev/dri/card0`.

Verify the running desktop:

```bash
workspace-desktop gpu
workspace-desktop health
```

If the renderer is unavailable, confirm the device path, GID, container runtime
permissions, and AMD Mesa support on the host.

## Local Chrome and Figma Desktop

Some design workflows need an application that must remain on the user's
computer. The helper script reverse-forwards dedicated local Chrome DevTools and
Figma Desktop MCP ports into the workspace for the duration of an SSH session:

```bash
./scripts/tunnel-local-services.sh my-workspace
```

Read [docs/local-services.md](docs/local-services.md) before enabling it. Use a
dedicated Chrome debugging profile, trust every process in the workspace while
the tunnel is open, and never share ports 9222 or 3845.

## Add or modify a feature

Features live under `template/modules/root/NAME` or
`template/modules/userspace/NAME`. Every feature has a literal `Dockerfile`;
optional `init` and `bash_config` fragments are concatenated in profile order.

After changing a feature:

1. add it to a test profile at the intended order;
2. run the profile check and unit tests;
3. generate into a fresh directory;
4. inspect the generated Dockerfile and Terraform;
5. build the image and create a smoke-test workspace.

See [template/EXTENDING.md](template/EXTENDING.md) for the full contract.

## Updating a published template

Rebuild the image with a new immutable tag when possible, update the profile,
generate a fresh output, and push the new template version. Reusing `latest`
can make rollback and provenance harder.

`/home` is a persistent named volume. Updating the image does not overwrite an
existing user's files or shell configuration seeded into that volume. Test
changes both with a new workspace and with an update path before broad release.

## Validation

Run the repository checks:

```bash
PYTHONDONTWRITEBYTECODE=1 \
  python3 -m unittest discover -s template/tests -v

bash -n scripts/tunnel-local-services.sh

python3 template/assemble.py \
  --profile template/profiles/base.json \
  --check

python3 template/assemble.py \
  --profile template/profiles/web-prototype.json \
  --check
```

When Terraform is installed, format-check the source and generated files:

```bash
terraform fmt -check -recursive template/base/terraform
terraform fmt -check -recursive generated/web-prototype/terraform
```

Release acceptance requires live Base and Web Prototype workspaces. Verify:

- repository URL blank and repository URL supplied;
- browser IDE opens the intended directory;
- `/home` persists across stop/start;
- Preview reaches a server on port 3000 and remains owner-only;
- Workspace Desktop starts and passes `workspace-desktop health`;
- Playwright installs a project-owned Chromium and opens it visibly;
- stopping the workspace removes its container while retaining its volume.

## Troubleshooting

### Workspace remains “Connecting”

Confirm that the container can reach `CODER_ACCESS_URL`, the Docker provider is
using the correct socket, and the provisioner has permission to create
containers and volumes.

### Preview returns a connection error

The template does not start a development server. Check the listening port:

```bash
printf 'expected port: %s\n' "$WORKSPACE_PREVIEW_PORT"
lsof -iTCP:"$WORKSPACE_PREVIEW_PORT" -sTCP:LISTEN
```

Then check the project's command and logs. If it uses another port, use Coder's
detected-port interface or change the profile and republish the template.

### Desktop app is unavailable

Run:

```bash
workspace-desktop status
workspace-desktop health
```

Inspect logs under `~/.local/state/workspace-desktop/log`. Confirm that the
wildcard app domain resolves and that the template image matches the selected
profile.

### Repository clone fails

Check the immutable repository URL, user SSH key or external-auth setup, and the
Git-clone logs under `~/.coder-modules/coder/git-clone/`. Create a new workspace
after correcting an immutable URL.

### Docker build changes unexpectedly

The lock file hashes repository sources but external Debian repositories and
installer endpoints can change. Use immutable image tags/digests and pin or
mirror third-party installers when stronger reproducibility is required.

## Security and production boundary

The workspace is an isolated prototyping environment, not an application
deployment platform. AI-generated work must receive engineering review,
security hardening, dependency review, testing, accessibility validation, and
an owned production deployment before release.

Do not place production data, unrestricted credentials, or privileged host
devices into a general prototyping workspace. Keep Preview, Desktop, VNC, CDP,
and MCP endpoints private unless an administrator has deliberately designed and
reviewed a broader sharing policy.
