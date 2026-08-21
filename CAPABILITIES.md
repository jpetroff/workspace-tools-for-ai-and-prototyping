# Capabilities and roadmap

[Coder](https://coder.com/) provides excellent base for assembling workspaces. Here you can find customizable building blocks specifically for each use-case and way to customize them.

This page covers only technical building blocks of the tooling framework. **If you are looking for practical setup suggestions**, i.e. how to start using your Codex Desktop app along with a workspace, check WORKFLOW-SETUP.md.

## Available now

### Task-oriented workspace profiles

| Profile       | Best for                        | Included experience                                          |
| ------------- | ------------------------------- | ------------------------------------------------------------ |
| Base          | CLI tools, code review, scripts | code-server, Git, native build tools, Bun, uv, Linuxbrew     |
| Web Prototype | PM and designer web prototypes  | Base plus private preview, Playwright, fonts, X11 desktop    |
| Desktop App   | Tauri prototypes                | Base plus Tauri libraries, native debugging, Wayland desktop |

AMD GPU variants are available for administrators who can safely expose a DRM
render node. The normal defaults use no GPU or software rendering and work on a
broader range of Docker hosts.

### Optional repository cloning

The workspace creation form accepts an optional Git repository URL. Coder's
official Git-clone module clones it into `~/projects`; a blank workspace opens
`~/project`. The template deliberately does not guess an install command or run
repository code automatically.

Coder supplies each user with an SSH key and supports external authentication
for Git providers. See [Coder external auth](https://coder.com/docs/admin/external-auth).

### Browser IDE and persistent files

`code-server` opens the selected project in a browser. A named Docker volume
persists `/home`, so source files, caches, and settings survive workspace stops.
Creating a different workspace provides a clean project boundary.

Each image comes with [Linuxbrew](https://docs.brew.sh/Homebrew-on-Linux) package manager preinstalled. From there you can install anything safely after the workspace is created and keep it installed. Workspaces are personalized extensions of personal development environment, not a production build. They are not meant to be ‘immutable’. They evolve with the user, tools and functionality can be added at any point on demand just like you would on your own device. 

```sh
> brew install …
```

This should get you pretty much anything you need ;) 

### Known preview URL

Web profiles expose an owner-only `Preview` app and set
`WORKSPACE_PREVIEW_PORT=3000`. The developer or AI assistant still starts the
project's development server. Coder can discover other listening ports when a
project uses a different convention. See [Coder port forwarding](https://coder.com/docs/user-guides/workspace-access/port-forwarding).

### Interactive remote desktops

The X11 and Wayland backends provide a browser-accessible noVNC desktop for
headed browser work and Linux desktop applications. Desktop services run as the
unprivileged `coder` user, bind to workspace loopback, and are exposed through
an owner-only Coder app.

Desktop starts automatically on workspace launch, logs and status shown within Coder interface. 

```sh
> workspace-desktop -h
Usage:
  workspace-desktop start [--size WIDTHxHEIGHT]
  workspace-desktop stop
  workspace-desktop restart [--size WIDTHxHEIGHT]
  workspace-desktop status
  workspace-desktop health
  workspace-desktop gpu
  workspace-desktop logs [dbus|sway|wayvnc|novnc]
  workspace-desktop env
  workspace-desktop run APPLICATION [ARGUMENT...]
```

### Fonts

This repository contains only Linux default fonts for GNOME desktop for licensing reasons. You can always add Windows and Macos default fonts personally for development reasons (and under development license directly from either party). These fonts are bundled into the images and can be changed:

```sh
> workspace-font -h
Usage:
  workspace-font
  workspace-font --system FAMILY --monospace FAMILY [--size POINTS]
  workspace-font --list
  workspace-font --list-monospace
  workspace-font --show

With no arguments, choose the default UI and monospace families interactively.
The chooser uses fzf when available and falls back to a numbered menu.
```

### Browser automation

Playwright profiles include Python and Chromium's operating-system libraries.
Each repository installs its own Playwright package and matching browser binary,
preventing library/browser revision drift. The `playwright-browser` helper opens
a persistent headed Chromium instance for human or agent inspection.

### Desktop-app development

Tauri profiles include GTK, WebKitGTK, GStreamer, Rust-compatible native build
dependencies, GDB/LLDB, and VS Code launch/task defaults. Software-rendered and
AMD GPU options use the same workspace desktop interface.

### Git identity and secrets

Coder owner metadata becomes the default Git author/committer identity. Coder
user secrets can inject API keys as environment variables or files at workspace
start; secret values never belong in profile JSON or visible template
parameters. See [Coder user secrets](https://coder.com/docs/user-guides/user-secrets).

### Local Chrome and Figma connections

The optional [local-services tunnel](docs/local-services.md) reverse-forwards a
dedicated local Chrome DevTools endpoint and Figma Desktop MCP into the
workspace. The tunnel lasts only for the SSH session and never publishes those
control ports as workspace apps.

### Composable, reviewable images

The dependency-free Python assembler validates profiles, preserves feature
order, writes a standalone build context, and records source hashes. Feature
Dockerfile fragments stay readable and independently cacheable.

## Roadmap and optional extensions

These are deliberately not enabled by default. Each introduces product,
credential, policy, or infrastructure choices an administrator must own.

### Selectable AI assistants

Offer organization-approved launchers through [Coder Agents](https://coder.com/docs/ai-coder/agents)
or pinned Registry modules such as Claude Code or Codex. A production design
must choose authentication, model access, network policy, telemetry, and safe
defaults rather than embedding personal API keys.

Alternatively install via Linuxbrew a tool of your choice after creating a workspace, i.e. `brew install codex`. 

### Guided presets and prebuilt workspaces

Use [workspace presets](https://coder.com/docs/admin/templates/extending-templates/parameters)
to present task names instead of infrastructure choices. Larger installations
can add prebuilt workspace pools to reduce startup time and scheduling policies
to control idle cost.

### Friendly file operations

Add Coder's official file-browser module for people who are uncomfortable with
Git or a terminal. Define explicit upload, download, retention, and handoff
rules before treating it as the source of truth.

### Databases and representative data

Provide optional disposable databases, schema migration helpers, fixtures, and
reset buttons. Use synthetic or approved data only; prototypes should never
receive production credentials or unrestricted customer data.

### Design-system and Figma workflows

Add organization-owned design tokens, component packages, and hosted Figma MCP
configuration. The existing local tunnel can support selection-based desktop
workflows, but shared deployments need access controls and versioned design
inputs.

### Automated quality feedback

Expose accessibility scans, visual regression images, test reports, and browser
console/network failures as workspace apps or build artifacts. These checks can
help non-experts recover from failures but do not replace engineering review.

### Controlled preview sharing

The current preview is owner-only. Authenticated team or public sharing should
be a separate policy decision with explicit data, secret, abuse, and lifecycle
controls.

### Production handoff

Add a reviewed handoff workflow that records requirements, generated changes,
tests, known limitations, dependency provenance, and a security review. The
workspace can accelerate discovery; production release remains an engineering
process.