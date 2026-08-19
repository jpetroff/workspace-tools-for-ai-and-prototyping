# Coder AI Workspaces

Create a ready-to-use workspace when an idea needs more than a mockup.

Coder AI Workspaces gives product managers, product designers, and developers a
consistent place to build, preview, test, and inspect AI-assisted prototypes.
The tools run on a Coder-managed Docker host, while the browser provides the
editor, terminal, live preview, and—when needed—a full Linux desktop.

No one has to repeat project-by-project setup for SSH access, Linux packages,
browser automation, desktop services, or common language toolchains. A Coder
administrator prepares the templates once; workspace users choose a profile
and begin with a clean or cloned project.

## The experience

1. Create a **Web Prototype**, **Desktop App**, or **Base** workspace.
2. Optionally paste a Git repository URL. Leave it blank to start fresh.
3. Open the browser IDE and work with your preferred AI coding assistant.
4. Ask the project to run on `$WORKSPACE_PREVIEW_PORT`—port `3000` by default.
5. Open **Preview** or **Workspace Desktop** from the Coder dashboard.
6. Run tests, inspect failures, and iterate without changing your local setup.
7. Stop the workspace when finished; its project files remain on its persistent
   volume.

The template clones repositories but does not automatically install
dependencies or execute project code. That keeps startup understandable and
lets each project—or its AI assistant—follow the repository's own instructions.

## Who it helps

### Product managers

- Turn a written workflow into a testable prototype before committing
  engineering capacity.
- Validate interaction details and edge cases instead of relying only on static
  screens.
- Share concrete findings and reproducible project state with engineers.

### Product designers

- Move from Figma or a design system to a functioning browser or Tauri
  prototype.
- Inspect responsive behavior, real content, keyboard flow, browser errors, and
  accessibility checks.
- Use a headed browser or Linux desktop without installing the same stack on a
  personal computer.

### Developers and AI assistants

- Work in the same image, toolchain, filesystem, ports, and desktop services.
- Run Git, builds, tests, debuggers, Playwright, and supported GUI applications
  as in a normal Linux development environment.
- Recreate a workspace from a versioned profile instead of documenting a long
  manual setup checklist.

## Included profiles

| Profile | Use it for | Highlights |
| --- | --- | --- |
| Base | Scripts, code review, services | Browser IDE, Git, Bun, uv, Linuxbrew, native build tools |
| Web Prototype | Websites and interactive product concepts | Private preview, Playwright, fonts, browser desktop |
| Desktop App | Tauri application prototypes | Wayland desktop, GTK/WebKit, native debugging |

Advanced AMD GPU variants are available for administrators with a compatible
Linux host. The normal profiles do not require host GPU configuration.

## What “local-like” means

The workspace supports ordinary Git, terminal, build, test, browser automation,
debugging, and selected Linux GUI workflows. It does not provide unrestricted
access to every device or application on the user's computer. Local Chrome and
Figma Desktop can be connected through an explicit, temporary SSH tunnel when
that workflow is needed.

Coder provides generated SSH keys, browser IDEs, private workspace apps,
persistent storage, port discovery, and secret injection. This repository adds
the task-oriented images, desktops, Playwright/Tauri features, preview
convention, and profile assembler.

## Get started

Workspace users need access to a published template. Administrators and
developers should follow the detailed [setup guide](setup.md) to:

- configure a Coder deployment with a Docker host and wildcard app domain;
- validate and assemble a profile;
- build the image and publish its Terraform template;
- configure Git authentication and secret handling;
- verify preview, desktop, Playwright, and GPU behavior.

See [Capabilities and roadmap](CAPABILITIES.md) for the exact current feature
set, researched user needs, and intentionally deferred extensions. Template
authors can start with the [assembler reference](template/README.md).

## Prototype-first boundary

AI-assisted building makes functional prototypes faster; it does not turn them
into production systems. Before release, an engineer should review the code,
dependencies, authentication, data handling, accessibility, error states,
tests, deployment configuration, and operational ownership.

Research with non-expert programmers and UX professionals reports real gains in
iteration alongside difficulty debugging, integrating, and judging generated
code. This project reduces environment friction while keeping verification and
handoff visible:

- [Non-Expert Programmers in the Generative AI Future](https://www.feldmanmolly.com/chiwork2024-author-version.pdf)
- [Vibe Coding for UX Design](https://arxiv.org/abs/2509.10652)
- [Figma's 2025 AI report](https://www.figma.com/reports/ai-2025/)

## License

MIT. See [LICENSE](LICENSE).
