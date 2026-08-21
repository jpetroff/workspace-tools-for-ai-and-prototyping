# Workspace fonts

Font files anywhere below this module are copied recursively into
`/usr/local/share/fonts/workspace` when the workspace image is built. The build
uses `fc-scan`, so supported font files are detected by their contents rather
than by a fixed filename-extension list. The `linux_default` directory is a
working example: add another directory next to it, place fonts in any nested
layout, assemble the profile, and rebuild the image.

Windows and macOS fonts are intentionally not included because their licenses
generally do not permit redistribution in this template. Users who have the
right to use those fonts can copy their own files into directories such as
`windows/` or `macos/` before building the workspace image. Keep any required
license files alongside them; non-font files are ignored by the installer.

The image also provides `workspace-font`, an interactive selector for testing
designs against installed system fonts. It updates the user's Fontconfig
`sans-serif` and `monospace` aliases, sets the GTK 3/4 UI font, and reloads a
running Sway or Openbox session when possible:

```bash
workspace-font
workspace-font --show
workspace-font --list
workspace-font --system "Arial" --monospace "Consolas"
```

Sway and Openbox use the generic `sans-serif` alias in their checked-in
configuration. The Openbox terminal command and foot's default configuration
use the generic `monospace` alias. Existing applications can cache font
settings, so reopen them after changing the selection.
