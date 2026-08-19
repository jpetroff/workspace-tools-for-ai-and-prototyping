#!/usr/bin/env python3
"""Assemble a Coder workspace image from ordered Dockerfile features."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shlex
import shutil
import sys
import tempfile
from pathlib import Path
from typing import Any, Iterable


SCHEMA_VERSION = 2
ROOT_MARKER = "# {{ROOT_FEATURES}}"
USERSPACE_MARKER = "# {{USERSPACE_FEATURES}}"
DISPLAY_BACKENDS = {"none", "wayland-gpu", "wayland-software", "x11-openbox"}
CODER_MODULES = {"code-server", "jetbrains"}
ROOT_KEYS = {
    "$schema",
    "schema_version",
    "name",
    "description",
    "image",
    "features",
    "display",
    "preview",
    "playwright",
    "coder_modules",
    "native_debug",
    "shm_size_mb",
}
NAME_RE = re.compile(r"^[a-z][a-z0-9-]*$")
IMAGE_RE = re.compile(r"^[A-Za-z0-9._/:@-]+$")
SCREEN_RE = re.compile(r"^[1-9][0-9]*x[1-9][0-9]*$")
DEVICE_RE = re.compile(r"^/dev/dri/renderD[0-9]+$")


class ProfileError(ValueError):
    """Raised when a profile or selected feature is invalid."""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate a standalone Docker/Coder workspace directory."
    )
    parser.add_argument("--profile", required=True, type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument(
        "--check",
        action="store_true",
        help="Validate the profile and selected feature folders without writing.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Replace an existing directory created by this assembler.",
    )
    return parser.parse_args()


def require_type(value: Any, expected: type, path: str) -> None:
    if not isinstance(value, expected) or expected is int and isinstance(value, bool):
        raise ProfileError(f"{path} must be {expected.__name__}")


def require_keys(value: dict[str, Any], keys: Iterable[str], path: str) -> None:
    missing = sorted(set(keys) - value.keys())
    if missing:
        raise ProfileError(f"{path} is missing: {', '.join(missing)}")


def reject_unknown_keys(value: dict[str, Any], allowed: set[str], path: str) -> None:
    unknown = sorted(value.keys() - allowed)
    if unknown:
        raise ProfileError(f"{path} contains unknown keys: {', '.join(unknown)}")


def validate_names(value: Any, path: str) -> list[str]:
    require_type(value, list, path)
    if not all(isinstance(item, str) for item in value):
        raise ProfileError(f"{path} must contain only strings")
    if len(set(value)) != len(value):
        raise ProfileError(f"{path} contains duplicate names")
    invalid = [name for name in value if not NAME_RE.fullmatch(name)]
    if invalid:
        raise ProfileError(
            f"{path} contains invalid feature names: {', '.join(invalid)}"
        )
    return value


def load_profile(path: Path) -> dict[str, Any]:
    try:
        profile = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise ProfileError(f"profile not found: {path}") from exc
    except json.JSONDecodeError as exc:
        raise ProfileError(f"invalid JSON in {path}: {exc}") from exc

    require_type(profile, dict, "profile")
    reject_unknown_keys(profile, ROOT_KEYS, "profile")
    require_keys(
        profile,
        {
            "schema_version",
            "name",
            "description",
            "image",
            "features",
            "display",
            "coder_modules",
            "native_debug",
            "shm_size_mb",
        },
        "profile",
    )
    if profile["schema_version"] != SCHEMA_VERSION:
        raise ProfileError(f"schema_version must be {SCHEMA_VERSION}")

    if "$schema" in profile:
        require_type(profile["$schema"], str, "$schema")

    for key in ("name", "description", "image"):
        require_type(profile[key], str, key)
    if not NAME_RE.fullmatch(profile["name"]):
        raise ProfileError("name must use lowercase letters, digits and hyphens")
    if not profile["description"].strip():
        raise ProfileError("description must not be empty")
    if not IMAGE_RE.fullmatch(profile["image"]):
        raise ProfileError("image contains unsupported characters")

    features = profile["features"]
    require_type(features, dict, "features")
    reject_unknown_keys(features, {"root", "userspace"}, "features")
    require_keys(features, {"root", "userspace"}, "features")
    root_features = validate_names(features["root"], "features.root")
    userspace_features = validate_names(features["userspace"], "features.userspace")
    selected_features = root_features + userspace_features

    coder_modules = validate_names(profile["coder_modules"], "coder_modules")
    unknown_modules = sorted(set(coder_modules) - CODER_MODULES)
    if unknown_modules:
        raise ProfileError(f"unknown coder_modules: {', '.join(unknown_modules)}")
    if "code-server" not in coder_modules:
        raise ProfileError("coder_modules must include code-server")

    require_type(profile["native_debug"], bool, "native_debug")
    require_type(profile["shm_size_mb"], int, "shm_size_mb")
    if not 64 <= profile["shm_size_mb"] <= 65536:
        raise ProfileError("shm_size_mb must be between 64 and 65536")

    display = profile["display"]
    require_type(display, dict, "display")
    reject_unknown_keys(
        display,
        {"backend", "autostart", "screen_size", "vnc_port", "novnc_port", "gpu"},
        "display",
    )
    require_keys(
        display,
        {"backend", "autostart", "screen_size", "vnc_port", "novnc_port"},
        "display",
    )
    if display["backend"] not in DISPLAY_BACKENDS:
        raise ProfileError(f"unknown display backend: {display['backend']!r}")
    require_type(display["autostart"], bool, "display.autostart")
    require_type(display["screen_size"], str, "display.screen_size")
    if not SCREEN_RE.fullmatch(display["screen_size"]):
        raise ProfileError("display.screen_size must be WIDTHxHEIGHT")
    for key in ("vnc_port", "novnc_port"):
        require_type(display[key], int, f"display.{key}")
        if not 1 <= display[key] <= 65535:
            raise ProfileError(f"display.{key} must be between 1 and 65535")
    if display["vnc_port"] == display["novnc_port"]:
        raise ProfileError("display VNC and noVNC ports must differ")
    if display["backend"] == "none" and display["autostart"]:
        raise ProfileError("display.autostart cannot be true when backend is none")

    gpu = display.get("gpu")
    if display["backend"] == "wayland-gpu":
        require_type(gpu, dict, "display.gpu")
        reject_unknown_keys(gpu, {"render_device"}, "display.gpu")
        require_keys(gpu, {"render_device"}, "display.gpu")
        require_type(gpu["render_device"], str, "display.gpu.render_device")
        if not DEVICE_RE.fullmatch(gpu["render_device"]):
            raise ProfileError("display.gpu.render_device must be a DRM render node")
    elif gpu is not None:
        raise ProfileError("display.gpu is allowed only for wayland-gpu")

    preview = profile.get("preview")
    if preview is not None:
        require_type(preview, dict, "preview")
        reject_unknown_keys(preview, {"enabled", "port"}, "preview")
        require_keys(preview, {"enabled", "port"}, "preview")
        require_type(preview["enabled"], bool, "preview.enabled")
        require_type(preview["port"], int, "preview.port")
        if not 1 <= preview["port"] <= 65535:
            raise ProfileError("preview.port must be between 1 and 65535")

    playwright = profile.get("playwright")
    if "playwright" in selected_features:
        require_type(playwright, dict, "playwright")
        reject_unknown_keys(playwright, {"deps_version"}, "playwright")
        require_keys(playwright, {"deps_version"}, "playwright")
        require_type(playwright["deps_version"], str, "playwright.deps_version")
        if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", playwright["deps_version"]):
            raise ProfileError("playwright.deps_version must be a semantic version")
    elif playwright is not None:
        raise ProfileError("playwright settings require the playwright feature")

    return profile


def feature_paths(root: Path, profile: dict[str, Any]) -> list[tuple[str, str, Path]]:
    selected: list[tuple[str, str, Path]] = []
    for section in ("root", "userspace"):
        for name in profile["features"][section]:
            path = root / "modules" / section / name
            if not path.is_dir():
                raise ProfileError(
                    f"feature folder does not exist: modules/{section}/{name}"
                )
            if not (path / "Dockerfile").is_file():
                raise ProfileError(
                    f"feature is missing its Dockerfile slice: modules/{section}/{name}"
                )
            selected.append((section, name, path))
    return selected


def feature_block(section: str, features: list[tuple[str, str, Path]]) -> str:
    selected = [item for item in features if item[0] == section]
    if not selected:
        return f"# No {section} features selected."
    blocks: list[str] = []
    for index, (_, name, path) in enumerate(selected, start=1):
        fragment = (path / "Dockerfile").read_text(encoding="utf-8").strip()
        if not fragment:
            raise ProfileError(f"empty Dockerfile slice: modules/{section}/{name}")
        blocks.append(
            "\n".join(
                [
                    "# ============================================================",
                    f"# {section.capitalize()} feature {index}/{len(selected)}: {name}",
                    f"# Source: modules/{section}/{name}/Dockerfile",
                    "# ============================================================",
                    fragment,
                ]
            )
        )
    return "\n\n".join(blocks)


def render_dockerfile(template: str, features: list[tuple[str, str, Path]]) -> str:
    for marker in (ROOT_MARKER, USERSPACE_MARKER):
        if template.count(marker) != 1:
            raise ProfileError(f"base/Dockerfile must contain exactly one {marker}")
    rendered = template.replace(ROOT_MARKER, feature_block("root", features))
    rendered = rendered.replace(USERSPACE_MARKER, feature_block("userspace", features))
    return rendered.rstrip() + "\n"


def concatenate_feature_file(
    features: list[tuple[str, str, Path]], filename: str, *, executable: bool
) -> str:
    content = ["#!/usr/bin/env bash", "", "set -Eeuo pipefail", ""] if executable else []
    for section, name, path in features:
        fragment_path = path / filename
        if not fragment_path.is_file():
            continue
        fragment = fragment_path.read_text(encoding="utf-8").strip()
        if not fragment:
            continue
        content.extend(
            [
                f"# ---- {section} feature: {name} ----",
                fragment,
                "",
            ]
        )
    return "\n".join(content).rstrip() + "\n"


def discover_scripts(features: list[tuple[str, str, Path]]) -> list[str]:
    scripts: list[str] = []
    for _, _, path in features:
        bin_dir = path / ".local/bin"
        if not bin_dir.is_dir():
            continue
        for script in sorted(item for item in bin_dir.iterdir() if item.is_file()):
            if script.name not in scripts and script.name != "workspace-init":
                scripts.append(script.name)
    return scripts


def shell_value(value: Any) -> str:
    if isinstance(value, bool):
        value = "1" if value else "0"
    return shlex.quote(str(value))


def render_profile_env(profile: dict[str, Any]) -> str:
    display = profile["display"]
    gpu = display.get("gpu", {})
    backend = display["backend"]
    features = profile["features"]["root"] + profile["features"]["userspace"]
    render_mode = {
        "none": "none",
        "wayland-gpu": "gpu",
        "wayland-software": "software",
        "x11-openbox": "software",
    }[backend]
    values = {
        "WORKSPACE_PROFILE_NAME": profile["name"],
        "WORKSPACE_DESCRIPTION": profile["description"],
        "WORKSPACE_DISPLAY_BACKEND": backend,
        "WORKSPACE_DESKTOP_AUTOSTART": display["autostart"],
        "WORKSPACE_RENDER_MODE": render_mode,
        "WORKSPACE_FEATURES": ",".join(features),
        "SCREEN_SIZE": display["screen_size"],
        "VNC_PORT": display["vnc_port"],
        "NOVNC_PORT": display["novnc_port"],
        "NOVNC_BIND": "127.0.0.1",
        "GPU_RENDER_DEVICE": gpu.get("render_device", ""),
        "PLAYWRIGHT_DEPS_VERSION": profile.get("playwright", {}).get("deps_version", ""),
    }
    if backend != "none":
        values["DISPLAY"] = ":0"
    if backend.startswith("wayland-"):
        values["WAYLAND_DISPLAY"] = "wayland-1"
    if "playwright" in features:
        values["PLAYWRIGHT_BROWSERS_PATH"] = "/home/coder/.cache/ms-playwright"
    preview = profile.get("preview", {})
    if preview.get("enabled", False):
        values["WORKSPACE_PREVIEW_PORT"] = preview["port"]
    return "".join(f"export {key}={shell_value(value)}\n" for key, value in values.items())


def hcl(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, list):
        return "[" + ", ".join(hcl(item) for item in value) + "]"
    return str(value)


def render_profile_tf(profile: dict[str, Any]) -> str:
    display = profile["display"]
    gpu = display.get("gpu", {})
    root_features = profile["features"]["root"]
    userspace_features = profile["features"]["userspace"]
    values = {
        "name": profile["name"],
        "description": profile["description"],
        "image": profile["image"],
        "display_backend": display["backend"],
        "desktop_enabled": display["backend"] != "none",
        "desktop_autostart": display["autostart"],
        "screen_size": display["screen_size"],
        "vnc_port": display["vnc_port"],
        "novnc_port": display["novnc_port"],
        "gpu_enabled": display["backend"] == "wayland-gpu",
        "render_device_default": gpu.get("render_device", ""),
        "preview_enabled": profile.get("preview", {}).get("enabled", False),
        "preview_port": profile.get("preview", {}).get("port", 3000),
        "root_features": root_features,
        "userspace_features": userspace_features,
        "features": root_features + userspace_features,
        "coder_modules": profile["coder_modules"],
        "native_debug": profile["native_debug"],
        "shm_size_mb": profile["shm_size_mb"],
    }
    width = max(len(key) for key in values)
    lines = [
        "# Generated by template/assemble.py; edit the source profile instead.",
        "locals {",
        "  workspace_profile = {",
        *(f"    {key.ljust(width)} = {hcl(value)}" for key, value in values.items()),
        "  }",
        "}",
        "",
    ]
    return "\n".join(lines)


def render_readme(profile: dict[str, Any]) -> str:
    root_features = profile["features"]["root"]
    userspace_features = profile["features"]["userspace"]
    return f"""# {profile['name']}

{profile['description']}

Generated by `template/assemble.py` from an ordered feature profile.

## Build and deploy

```bash
docker build -t {profile['image']} .
coder templates push {profile['name']} --directory ./terraform
```

Root features run in this exact order:

{os.linesep.join(f'{index}. `{name}`' for index, name in enumerate(root_features, 1)) or 'None.'}

Userspace features run in this exact order:

{os.linesep.join(f'{index}. `{name}`' for index, name in enumerate(userspace_features, 1)) or 'None.'}

The generated `features/` directory contains the selected source folders. Each
folder has its literal Dockerfile slice and direct home-relative paths such as
`.config/` and `.local/`; there is no `overlay/home/coder` indirection.

The Docker volume mounted at `/home` is initialized from the image only when it
is new. Existing workspace volumes retain their current user files.
"""


def hash_files(root: Path, paths: list[Path]) -> dict[str, str]:
    hashes: dict[str, str] = {}
    for path in sorted(set(paths)):
        if not path.is_file() or "__pycache__" in path.parts:
            continue
        try:
            key = path.relative_to(root).as_posix()
        except ValueError:
            key = f"profile/{path.name}"
        hashes[key] = hashlib.sha256(path.read_bytes()).hexdigest()
    return hashes


def collect_sources(
    root: Path, profile_path: Path, features: list[tuple[str, str, Path]]
) -> list[Path]:
    paths = [root / "assemble.py", root / "profile.schema.json", profile_path.resolve()]
    paths.extend(path for path in (root / "base").rglob("*") if path.is_file())
    for _, _, feature_path in features:
        paths.extend(path for path in feature_path.rglob("*") if path.is_file())
    return paths


def assemble(
    root: Path, profile_path: Path, profile: dict[str, Any], output: Path
) -> None:
    features = feature_paths(root, profile)
    output_parent = output.resolve().parent
    output_parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(
        prefix=f".{output.name}.assemble-", dir=output_parent
    ) as temporary:
        temporary_path = Path(temporary)
        context_base = temporary_path / "base"
        context_base.mkdir()

        for filename in (".bashrc", ".profile", "workspace-init"):
            shutil.copy2(root / "base" / filename, context_base / filename)
        shutil.copy2(root / "base/.dockerignore", temporary_path / ".dockerignore")
        terraform_dir = temporary_path / "terraform"
        terraform_dir.mkdir()
        shutil.copy2(
            root / "base/terraform/template.tf", terraform_dir / "template.tf"
        )
        shutil.copy2(
            root / "base/terraform/modules.tf", terraform_dir / "modules.tf"
        )

        for section, name, feature_path in features:
            target = temporary_path / "features" / section / name
            shutil.copytree(feature_path, target)

        profile_env = render_profile_env(profile)
        (context_base / "profile.env").write_text(profile_env, encoding="utf-8")
        (context_base / "bash_config").write_text(
            concatenate_feature_file(features, "bash_config", executable=False),
            encoding="utf-8",
        )
        (context_base / "init").write_text(
            concatenate_feature_file(features, "init", executable=True),
            encoding="utf-8",
        )
        scripts = discover_scripts(features)
        (context_base / "scripts").write_text(
            "".join(f"{script}\n" for script in scripts), encoding="utf-8"
        )

        dockerfile_template = (root / "base/Dockerfile").read_text(encoding="utf-8")
        (temporary_path / "Dockerfile").write_text(
            render_dockerfile(dockerfile_template, features), encoding="utf-8"
        )
        (terraform_dir / "profile.tf").write_text(
            render_profile_tf(profile), encoding="utf-8"
        )
        (temporary_path / "README.md").write_text(
            render_readme(profile), encoding="utf-8"
        )
        (temporary_path / ".workspace-image-generated").write_text(
            json.dumps(
                {
                    "generator": "template/assemble.py",
                    "profile": profile["name"],
                    "schema_version": SCHEMA_VERSION,
                },
                sort_keys=True,
            )
            + "\n",
            encoding="utf-8",
        )

        sources = collect_sources(root, profile_path, features)
        lock = {
            "schema_version": SCHEMA_VERSION,
            "profile": profile["name"],
            "root_features": profile["features"]["root"],
            "userspace_features": profile["features"]["userspace"],
            "scripts": scripts,
            "source_hashes": hash_files(root, sources),
        }
        (temporary_path / "profile.lock.json").write_text(
            json.dumps(lock, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )

        if output.exists():
            shutil.rmtree(output)
        os.replace(temporary_path, output)


def main() -> int:
    args = parse_args()
    root = Path(__file__).resolve().parent
    try:
        profile_path = args.profile.resolve()
        profile = load_profile(profile_path)
        features = feature_paths(root, profile)

        if args.check:
            print(f"profile: {profile['name']}")
            print("root features: " + ", ".join(profile["features"]["root"]))
            print("userspace features: " + ", ".join(profile["features"]["userspace"]))
            print("scripts: " + ", ".join(discover_scripts(features)))
            return 0

        if args.output is None:
            raise ProfileError("--output is required unless --check is used")
        output = args.output.resolve()
        if output == root or root in output.parents:
            raise ProfileError("output must not replace or be inside the template source")
        if output.exists() and not args.force:
            raise ProfileError(f"output already exists: {output}; use --force")
        if output.exists() and args.force:
            if not output.is_dir():
                raise ProfileError(f"output is not a directory: {output}")
            if not (output / ".workspace-image-generated").is_file():
                raise ProfileError(
                    "refusing to replace a directory not created by this generator"
                )

        assemble(root, profile_path, profile, output)
        print(f"generated {output}")
        return 0
    except ProfileError as exc:
        print(f"assemble: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
