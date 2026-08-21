from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


TEMPLATE_ROOT = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = TEMPLATE_ROOT.parent
ASSEMBLER_PATH = TEMPLATE_ROOT / "assemble.py"
SPEC = importlib.util.spec_from_file_location("workspace_assemble", ASSEMBLER_PATH)
assert SPEC is not None and SPEC.loader is not None
workspace_assemble = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(workspace_assemble)


class ProfileTests(unittest.TestCase):
    def setUp(self) -> None:
        self.base = json.loads(
            (TEMPLATE_ROOT / "profiles/base.json").read_text(encoding="utf-8")
        )

    def write_profile(self, directory: Path, profile: dict) -> Path:
        path = directory / "profile.json"
        path.write_text(json.dumps(profile), encoding="utf-8")
        return path

    def assert_profile_error(self, profile: dict, message: str) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = self.write_profile(Path(temporary), profile)
            with self.assertRaisesRegex(workspace_assemble.ProfileError, message):
                workspace_assemble.load_profile(path)

    def test_all_profiles_and_selected_folders_validate(self) -> None:
        paths = sorted((TEMPLATE_ROOT / "profiles").rglob("*.json"))
        self.assertEqual(len(paths), 5)
        for path in paths:
            with self.subTest(profile=path.name):
                profile = workspace_assemble.load_profile(path)
                features = workspace_assemble.feature_paths(TEMPLATE_ROOT, profile)
                self.assertEqual(
                    [section for section, _, _ in features],
                    ["root"] * len(profile["features"]["root"])
                    + ["userspace"] * len(profile["features"]["userspace"]),
                )

    def test_feature_names_are_not_enumerated_in_schema(self) -> None:
        schema = json.loads(
            (TEMPLATE_ROOT / "profile.schema.json").read_text(encoding="utf-8")
        )
        feature_schema = schema["properties"]["features"]
        self.assertNotIn('"enum"', json.dumps(feature_schema))

    def test_feature_discovery_accepts_any_existing_folder(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            feature = root / "modules/root/company-tools"
            feature.mkdir(parents=True)
            (feature / "Dockerfile").write_text("RUN true\n", encoding="utf-8")
            profile = copy.deepcopy(self.base)
            profile["features"] = {"root": ["company-tools"], "userspace": []}
            selected = workspace_assemble.feature_paths(root, profile)
            self.assertEqual(selected[0][1], "company-tools")

            profile["features"]["root"].append("missing")
            with self.assertRaisesRegex(
                workspace_assemble.ProfileError, "feature folder does not exist"
            ):
                workspace_assemble.feature_paths(root, profile)

    def test_invalid_display_and_playwright_combinations_fail(self) -> None:
        profile = copy.deepcopy(self.base)
        profile["display"]["autostart"] = True
        self.assert_profile_error(profile, "autostart cannot be true")

        profile = copy.deepcopy(self.base)
        profile["features"]["root"].append("playwright")
        self.assert_profile_error(profile, "playwright must be dict")

    def test_preview_configuration_is_optional_and_validated(self) -> None:
        profile = copy.deepcopy(self.base)
        self.assertNotIn("preview", workspace_assemble.load_profile(
            TEMPLATE_ROOT / "profiles/base.json"
        ))

        profile["preview"] = {"enabled": True, "port": 0}
        self.assert_profile_error(profile, "preview.port must be between")

        profile["preview"] = {"enabled": "yes", "port": 3000}
        self.assert_profile_error(profile, "preview.enabled must be bool")

    def test_unknown_profile_keys_fail(self) -> None:
        profile = copy.deepcopy(self.base)
        profile["typo"] = True
        self.assert_profile_error(profile, "unknown keys: typo")


class GenerationTests(unittest.TestCase):
    def file_hashes(self, root: Path) -> dict[str, str]:
        return {
            path.relative_to(root).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted(root.rglob("*"))
            if path.is_file()
        }

    def test_every_profile_generates_and_preserves_order(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            temporary_root = Path(temporary)
            for profile_path in sorted((TEMPLATE_ROOT / "profiles").rglob("*.json")):
                with self.subTest(profile=profile_path.name):
                    profile = workspace_assemble.load_profile(profile_path)
                    output = temporary_root / profile["name"]
                    workspace_assemble.assemble(
                        TEMPLATE_ROOT, profile_path, profile, output
                    )
                    dockerfile = (output / "Dockerfile").read_text(encoding="utf-8")
                    self.assertNotIn("{{ROOT_FEATURES}}", dockerfile)
                    self.assertNotIn("{{USERSPACE_FEATURES}}", dockerfile)

                    positions = []
                    for section in ("root", "userspace"):
                        for name in profile["features"][section]:
                            label = f"# Source: modules/{section}/{name}/Dockerfile"
                            positions.append(dockerfile.index(label))
                            self.assertTrue(
                                (output / f"features/{section}/{name}/Dockerfile").is_file()
                            )
                    self.assertEqual(positions, sorted(positions))
                    self.assertTrue((output / "base/.bashrc").is_file())
                    self.assertTrue((output / "base/.profile").is_file())
                    self.assertEqual(list(output.glob("*.tf")), [])
                    self.assertEqual(
                        sorted(
                            path.name for path in (output / "terraform").glob("*.tf")
                        ),
                        ["modules.tf", "profile.tf", "template.tf"],
                    )
                    readme = (output / "README.md").read_text(encoding="utf-8")
                    self.assertIn("--directory ./terraform", readme)

    def test_generation_is_deterministic_and_lock_hashes_assembler(self) -> None:
        profile_path = TEMPLATE_ROOT / "profiles/advanced/web-prototype-amd-gpu.json"
        profile = workspace_assemble.load_profile(profile_path)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            first = root / "first"
            second = root / "second"
            workspace_assemble.assemble(TEMPLATE_ROOT, profile_path, profile, first)
            workspace_assemble.assemble(TEMPLATE_ROOT, profile_path, profile, second)
            self.assertEqual(self.file_hashes(first), self.file_hashes(second))
            lock = json.loads((first / "profile.lock.json").read_text(encoding="utf-8"))
            expected = hashlib.sha256(ASSEMBLER_PATH.read_bytes()).hexdigest()
            self.assertEqual(lock["source_hashes"]["assemble.py"], expected)
            self.assertEqual(lock["root_features"], profile["features"]["root"])

    def test_dockerfile_contains_literal_cached_feature_layers(self) -> None:
        profile_path = TEMPLATE_ROOT / "profiles/advanced/web-prototype-amd-gpu.json"
        profile = workspace_assemble.load_profile(profile_path)
        features = workspace_assemble.feature_paths(TEMPLATE_ROOT, profile)
        template = (TEMPLATE_ROOT / "base/Dockerfile").read_text(encoding="utf-8")
        dockerfile = workspace_assemble.render_dockerfile(template, features)
        for section, name, path in features:
            with self.subTest(section=section, feature=name):
                fragment = (path / "Dockerfile").read_text(encoding="utf-8").strip()
                self.assertIn(fragment, dockerfile)
        self.assertIn(
            'RUN curl -fsSL https://starship.rs/install.sh | /bin/sh -s -- -y -b "/home/coder/.local/bin"',
            dockerfile,
        )
        self.assertIn("playwright install-deps chromium", dockerfile)
        self.assertNotIn("install.d", dockerfile)
        self.assertNotIn("packages.txt", dockerfile)

    def test_shell_and_init_fragments_are_concatenated_in_feature_order(self) -> None:
        profile_path = TEMPLATE_ROOT / "profiles/advanced/web-prototype-amd-gpu.json"
        profile = workspace_assemble.load_profile(profile_path)
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "output"
            workspace_assemble.assemble(TEMPLATE_ROOT, profile_path, profile, output)
            bash_config = (output / "base/bash_config").read_text(encoding="utf-8")
            self.assertLess(bash_config.index("root feature: core"), bash_config.index("root feature: wayland"))
            self.assertLess(bash_config.index("root feature: playwright"), bash_config.index("userspace feature: linuxbrew"))
            self.assertLess(bash_config.index("userspace feature: linuxbrew"), bash_config.index("userspace feature: starship"))
            init = (output / "base/init").read_text(encoding="utf-8")
            self.assertTrue(init.startswith("#!/usr/bin/env bash"))

    def test_starship_and_desktop_default_configs_are_present(self) -> None:
        expected = [
            "modules/userspace/starship/.config/starship.toml",
            "modules/root/desktop-common/.local/share/novnc/workspace-defaults.json",
            "modules/root/wayland/.config/sway/config",
            "modules/root/wayland/.config/wayvnc/config",
            "modules/root/x11-openbox/.config/openbox/rc.xml",
            "modules/root/x11-openbox/.config/openbox/autostart",
            "modules/root/x11-openbox/.config/x11vnc/config",
        ]
        for relative in expected:
            with self.subTest(path=relative):
                self.assertTrue((TEMPLATE_ROOT / relative).is_file())

    def test_fonts_install_packages_and_recursive_module_fonts(self) -> None:
        dockerfile = (TEMPLATE_ROOT / "modules/root/fonts/Dockerfile").read_text(
            encoding="utf-8"
        )
        for package in (
            "fonts-firacode",
            "fonts-liberation",
            "fonts-noto-color-emoji",
            "fonts-noto-core",
        ):
            self.assertIn(package, dockerfile)
        self.assertIn("COPY ./features/root/fonts/ /tmp/workspace-fonts/", dockerfile)
        self.assertIn("find . -type f", dockerfile)
        self.assertIn('fc-scan "$source"', dockerfile)
        self.assertIn("/usr/local/share/fonts/workspace", dockerfile)
        self.assertIn("fc-cache -f", dockerfile)
        self.assertTrue(
            list((TEMPLATE_ROOT / "modules/root/fonts/linux_default").rglob("*.ttf"))
        )

    def test_workspace_font_configures_fontconfig_and_gtk(self) -> None:
        script = TEMPLATE_ROOT / "modules/root/fonts/.local/bin/workspace-font"
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            home = root / "home"
            fake_bin = root / "bin"
            fake_bin.mkdir()

            commands = {
                "fc-list": """#!/bin/sh
case " $* " in
  *spacing*) printf 'Fira Code\\n' ;;
  *) printf 'Fira Code\\nLiberation Sans\\n' ;;
esac
""",
                "fc-match": """#!/bin/sh
case " $* " in
  *monospace*) printf 'Fira Code\\n' ;;
  *) printf 'Liberation Sans\\n' ;;
esac
""",
                "fc-cache": "#!/bin/sh\nexit 0\n",
                "pgrep": "#!/bin/sh\nexit 1\n",
            }
            for name, content in commands.items():
                command = fake_bin / name
                command.write_text(content, encoding="utf-8")
                command.chmod(0o755)

            result = subprocess.run(
                [
                    "bash",
                    str(script),
                    "--system",
                    "Liberation Sans",
                    "--monospace",
                    "Fira Code",
                ],
                check=False,
                capture_output=True,
                text=True,
                env={
                    **os.environ,
                    "HOME": str(home),
                    "XDG_CONFIG_HOME": str(home / ".config"),
                    "PATH": f"{fake_bin}:/usr/bin:/bin",
                },
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            fontconfig = (
                home / ".config/fontconfig/conf.d/20-workspace-defaults.conf"
            ).read_text(encoding="utf-8")
            self.assertIn("<family>Liberation Sans</family>", fontconfig)
            self.assertIn("<family>Fira Code</family>", fontconfig)
            for version in ("3.0", "4.0"):
                gtk = (home / f".config/gtk-{version}/settings.ini").read_text(
                    encoding="utf-8"
                )
                self.assertIn("gtk-font-name=Liberation Sans 10", gtk)
            self.assertIn("System font:    Liberation Sans", result.stdout)

    def test_bun_and_uv_install_and_bash_initialization(self) -> None:
        bun_dockerfile = (
            TEMPLATE_ROOT / "modules/userspace/bun/Dockerfile"
        ).read_text(encoding="utf-8")
        bun_bash = (
            TEMPLATE_ROOT / "modules/userspace/bun/bash_config"
        ).read_text(encoding="utf-8")
        uv_dockerfile = (
            TEMPLATE_ROOT / "modules/userspace/uv/Dockerfile"
        ).read_text(encoding="utf-8")
        uv_bash = (
            TEMPLATE_ROOT / "modules/userspace/uv/bash_config"
        ).read_text(encoding="utf-8")
        uvsh_path = TEMPLATE_ROOT / "modules/userspace/uv/.local/bin/uvsh"
        uvsh = uvsh_path.read_text(encoding="utf-8")

        self.assertIn(
            "RUN curl -fsSL https://bun.com/install | /bin/bash", bun_dockerfile
        )
        self.assertIn('export BUN_INSTALL="$HOME/.bun"', bun_bash)
        self.assertIn('export PATH="$BUN_INSTALL/bin:$PATH"', bun_bash)
        self.assertIn(
            'RUN /bin/bash -c "$(curl -fsSL https://astral.sh/uv/install.sh)"',
            uv_dockerfile,
        )
        self.assertIn('eval "$(uv generate-shell-completion bash)"', uv_bash)
        self.assertIn(
            'eval "$(uvx --generate-shell-completion bash)"', uv_bash
        )
        self.assertIn('uvinit() {', uv_bash)
        self.assertIn('. "$HOME/.local/bin/uvsh" "$@"', uv_bash)
        self.assertIn('venv_name="${1:-.venv}"', uvsh)
        self.assertIn('venv_name="${venv_name%?}"', uvsh)

        for profile_path in sorted((TEMPLATE_ROOT / "profiles").rglob("*.json")):
            profile = workspace_assemble.load_profile(profile_path)
            userspace = profile["features"]["userspace"]
            self.assertLess(userspace.index("linuxbrew"), userspace.index("bun"))
            self.assertLess(userspace.index("bun"), userspace.index("uv"))
            self.assertLess(userspace.index("uv"), userspace.index("starship"))

    def test_tauri_feature_installs_and_checks_gtk_development_metadata(self) -> None:
        dockerfile = (
            TEMPLATE_ROOT / "modules/root/tauri/Dockerfile"
        ).read_text(encoding="utf-8")
        for package in (
            "libatk1.0-dev",
            "libcairo2-dev",
            "libgdk-pixbuf-2.0-dev",
            "libglib2.0-dev",
            "libgtk-3-dev",
            "libpango1.0-dev",
            "libwebkit2gtk-4.1-dev",
            "pkg-config",
        ):
            with self.subTest(package=package):
                self.assertIn(package, dockerfile)
        for pkg_config_module in (
            "atk",
            "cairo",
            "gdk-3.0",
            "gdk-pixbuf-2.0",
            "gio-2.0",
            "glib-2.0",
            "gobject-2.0",
            "gtk+-3.0",
            "librsvg-2.0",
            "pango",
            "webkit2gtk-4.1",
        ):
            with self.subTest(pkg_config_module=pkg_config_module):
                self.assertIn(pkg_config_module, dockerfile)
        self.assertIn(
            "ln -s /usr/bin/pkg-config /usr/local/lib/tauri/bin/pkg-config",
            dockerfile,
        )
        self.assertIn("ENV PATH=/usr/local/lib/tauri/bin:${PATH}", dockerfile)
        self.assertIn("PKG_CONFIG=/usr/bin/pkg-config", dockerfile)
        self.assertIn("RUN /usr/bin/pkg-config --exists", dockerfile)

        bash_config = (
            TEMPLATE_ROOT / "modules/root/tauri/bash_config"
        ).read_text(encoding="utf-8")
        self.assertIn("dpkg-architecture -qDEB_HOST_MULTIARCH", bash_config)
        self.assertIn("export PKG_CONFIG=/usr/bin/pkg-config", bash_config)
        self.assertIn('export PKG_CONFIG_PATH', bash_config)
        self.assertNotIn("x86_64-linux-gnu", bash_config)

        result = subprocess.run(
            [
                "bash",
                "-c",
                "dpkg-architecture() { printf '%s' arm64-linux-gnu; }; "
                "PKG_CONFIG_PATH=/custom/pkgconfig; "
                '. "$1"; . "$1"; printf "%s" "$PKG_CONFIG_PATH"',
                "_",
                str(TEMPLATE_ROOT / "modules/root/tauri/bash_config"),
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout,
            "/usr/lib/arm64-linux-gnu/pkgconfig:"
            "/usr/lib/pkgconfig:/usr/share/pkgconfig:/custom/pkgconfig",
        )

    def test_uvsh_activates_in_the_current_shell(self) -> None:
        uvsh = TEMPLATE_ROOT / "modules/userspace/uv/.local/bin/uvsh"
        with tempfile.TemporaryDirectory() as temporary:
            venv = Path(temporary) / "my-venv"
            activator = venv / "bin/activate"
            activator.parent.mkdir(parents=True)
            activator.write_text("export UVSH_TEST_ACTIVE=yes\n", encoding="utf-8")

            result = subprocess.run(
                [
                    "bash",
                    "-c",
                    '. "$1" "$2/" && printf "%s" "$UVSH_TEST_ACTIVE"',
                    "_",
                    str(uvsh),
                    str(venv),
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(result.stdout.endswith("yes"))

            executed = subprocess.run(
                ["bash", str(uvsh)], check=False, capture_output=True, text=True
            )
            self.assertEqual(executed.returncode, 2)
            self.assertIn("must be sourced", executed.stderr)

    def test_module_layout_has_no_overlay_or_priority_names(self) -> None:
        priority_name = workspace_assemble.re.compile(r"^[0-9]+-")
        for path in (TEMPLATE_ROOT / "modules").rglob("*"):
            relative = path.relative_to(TEMPLATE_ROOT / "modules")
            with self.subTest(path=relative.as_posix()):
                self.assertNotIn("overlay", relative.parts)
                self.assertFalse(priority_name.match(path.name))
                if path.is_file() and path.name == "Dockerfile":
                    self.assertNotIn("#!/", path.read_text(encoding="utf-8"))

    def test_complete_shell_files_ignore_etc_skel_and_source_bash_config(self) -> None:
        bashrc = (TEMPLATE_ROOT / "base/.bashrc").read_text(encoding="utf-8")
        profile = (TEMPLATE_ROOT / "base/.profile").read_text(encoding="utf-8")
        init = (TEMPLATE_ROOT / "base/workspace-init").read_text(encoding="utf-8")
        dockerfile = (TEMPLATE_ROOT / "base/Dockerfile").read_text(encoding="utf-8")
        self.assertLess(bashrc.index("export XDG_CONFIG_HOME"), bashrc.index(".config/bash_config"))
        self.assertIn(".bashrc", profile)
        self.assertNotIn("/etc/skel", init)
        self.assertIn("/etc/skel is intentionally", dockerfile)
        self.assertNotIn("cp -rn /etc/skel", dockerfile)
        self.assertIn('"$HOME/project"', init)
        self.assertIn('"$HOME/projects"', init)

    def test_shell_welcome_lists_scripts_and_declared_functions(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            workspace_config = home / ".config/workspace"
            workspace_config.mkdir(parents=True)
            (home / ".config/bash_config").write_text(
                "workspace-example() { :; }\n", encoding="utf-8"
            )
            (workspace_config / "scripts").write_text(
                "workspace-script\n", encoding="utf-8"
            )

            result = subprocess.run(
                [
                    "bash",
                    "--noprofile",
                    "--rcfile",
                    str(TEMPLATE_ROOT / "base/.bashrc"),
                    "-i",
                    "-c",
                    "exit",
                ],
                check=False,
                capture_output=True,
                text=True,
                env={**os.environ, "HOME": str(home), "TERM": "dumb"},
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("Available scripts:", result.stdout)
            self.assertIn("workspace-script", result.stdout)
            self.assertIn("Available functions:", result.stdout)
            self.assertIn("workspace-example", result.stdout)

    def test_init_runs_once_then_is_renamed(self) -> None:
        script = TEMPLATE_ROOT / "base/workspace-init"
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary) / "home"
            config = home / ".config/workspace"
            config.mkdir(parents=True)
            (config / "init").write_text(
                'printf x >> "$HOME/init-runs"\n', encoding="utf-8"
            )
            environment = {**os.environ, "HOME": str(home)}
            subprocess.run(["bash", str(script)], env=environment, check=True)
            subprocess.run(["bash", str(script)], env=environment, check=True)
            self.assertEqual((home / "init-runs").read_text(encoding="utf-8"), "x")
            self.assertFalse((config / "init").exists())
            self.assertTrue((config / "init.done").is_file())

    def test_generated_terraform_retains_home_and_gpu_contracts(self) -> None:
        terraform = (
            TEMPLATE_ROOT / "base/terraform/template.tf"
        ).read_text(encoding="utf-8")
        self.assertIn('container_path = "/home"', terraform)
        self.assertIn("volume_name    = docker_volume.home.name", terraform)
        self.assertIn('host_path      = local.render_device', terraform)
        self.assertNotIn("/dev/dri/card0", terraform)
        self.assertNotIn("privileged", terraform)
        self.assertNotIn("workspace-startup", terraform)
        self.assertIn('data "coder_parameter" "repository_url"', terraform)
        self.assertIn('mutable      = false', terraform)
        self.assertIn('resource "coder_app" "preview"', terraform)
        self.assertIn('share        = "owner"', terraform)
        self.assertIn('subdomain    = true', terraform)

        modules = (
            TEMPLATE_ROOT / "base/terraform/modules.tf"
        ).read_text(encoding="utf-8")
        self.assertIn('module "git-clone"', modules)
        self.assertIn('version  = "2.0.2"', modules)
        self.assertIn('folder   = local.project_dir', modules)

    def test_preview_values_are_generated_only_for_web_profiles(self) -> None:
        web_path = TEMPLATE_ROOT / "profiles/web-prototype.json"
        base_path = TEMPLATE_ROOT / "profiles/base.json"
        web = workspace_assemble.load_profile(web_path)
        base = workspace_assemble.load_profile(base_path)

        self.assertRegex(
            workspace_assemble.render_profile_tf(web), r"preview_enabled\s+= true"
        )
        self.assertRegex(
            workspace_assemble.render_profile_tf(web), r"preview_port\s+= 3000"
        )
        self.assertIn(
            "export WORKSPACE_PREVIEW_PORT=3000",
            workspace_assemble.render_profile_env(web),
        )
        self.assertRegex(
            workspace_assemble.render_profile_tf(base), r"preview_enabled\s+= false"
        )
        self.assertNotIn("WORKSPACE_PREVIEW_PORT", workspace_assemble.render_profile_env(base))

    def test_gpu_gid_is_requested_in_coder_instead_of_profile_defaults(self) -> None:
        profile_path = TEMPLATE_ROOT / "profiles/advanced/web-prototype-amd-gpu.json"
        profile = workspace_assemble.load_profile(profile_path)
        self.assertEqual(profile["display"]["gpu"], {"render_device": "/dev/dri/renderD128"})
        profile_tf = workspace_assemble.render_profile_tf(profile)
        self.assertNotIn("render_gid_default", profile_tf)

        terraform = (
            TEMPLATE_ROOT / "base/terraform/template.tf"
        ).read_text(encoding="utf-8")
        gid_block = terraform.split('data "coder_parameter" "gpu_render_gid"', 1)[1]
        gid_block = gid_block.split('data "coder_parameter" "gpu_render_device"', 1)[0]
        self.assertNotIn("default", gid_block)

    def test_public_tree_has_no_personal_ca_or_font_artifacts(self) -> None:
        forbidden = ("192.168.", "STEP_CA_", "smallstep", "template-v2", "/Users/")
        for path in REPOSITORY_ROOT.rglob("*"):
            if (
                not path.is_file()
                or ".git" in path.parts
                or "__pycache__" in path.parts
                or path == Path(__file__)
            ):
                continue
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT).as_posix()):
                if path.suffix.lower() == ".ttf":
                    self.assertTrue(
                        path.is_relative_to(
                            TEMPLATE_ROOT / "modules/root/fonts/linux_default"
                        )
                    )
                    continue
                text = path.read_text(encoding="utf-8")
                for value in forbidden:
                    self.assertNotIn(value, text)

    def test_force_replaces_only_generated_directories(self) -> None:
        profile = TEMPLATE_ROOT / "profiles/base.json"
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "output"
            command = [
                sys.executable,
                str(ASSEMBLER_PATH),
                "--profile",
                str(profile),
                "--output",
                str(output),
            ]
            environment = {**os.environ, "PYTHONDONTWRITEBYTECODE": "1"}
            self.assertEqual(subprocess.run(command, env=environment, check=False).returncode, 0)
            self.assertEqual(subprocess.run(command, env=environment, check=False).returncode, 2)
            self.assertEqual(subprocess.run(command + ["--force"], env=environment, check=False).returncode, 0)

            unsafe = Path(temporary) / "unsafe"
            unsafe.mkdir()
            (unsafe / "keep.txt").write_text("user data", encoding="utf-8")
            unsafe_command = command[:-1] + [str(unsafe), "--force"]
            self.assertEqual(
                subprocess.run(unsafe_command, env=environment, check=False).returncode,
                2,
            )
            self.assertEqual((unsafe / "keep.txt").read_text(encoding="utf-8"), "user data")


if __name__ == "__main__":
    unittest.main()
