#!/usr/bin/env python3
"""Offline policy regressions through the contract checker's public --root CLI."""

import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CHECK = ROOT / "scripts/check-doc-contract.py"


class ToolUpdatePolicyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="sannux-policy-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        # Copy tracked source only, never local .env, agent state or build output.
        paths = subprocess.check_output(
            ["git", "ls-files", "-z"], cwd=ROOT, text=True
        ).split("\0")
        for relative in filter(None, paths):
            source = ROOT / relative
            if source.name.startswith(".env") and source.name != ".env.example":
                continue
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)

    def check(self) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(CHECK), "--root", str(self.root)],
            capture_output=True, text=True, timeout=30,
        )

    def reject_change(self, relative: str, old: str, new: str, message: str) -> None:
        path = self.root / relative
        original = path.read_text()
        self.assertIn(old, original)
        path.write_text(original.replace(old, new))
        try:
            result = self.check()
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn(message, result.stderr)
        finally:
            path.write_text(original)

    def test_current_channels_and_compatibility_contract_pass(self) -> None:
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_no_dockerfile_installs_rtk(self) -> None:
        dockerfiles = sorted((self.root / "templates").glob("*/Dockerfile"))
        self.assertEqual(len(dockerfiles), 10)
        for path in dockerfiles:
            with self.subTest(template=path.parent.name):
                self.assertNotRegex(path.read_text(), re.compile(r"\brtk\b", re.IGNORECASE))

    def test_every_template_rejects_tool_pins(self) -> None:
        for path in sorted((self.root / "templates").glob("*/Dockerfile")):
            relative = str(path.relative_to(self.root))
            for old, new, message in [
                ("ENV DEBIAN_FRONTEND", "ARG TOOL_VERSION=1.2.3\nENV DEBIAN_FRONTEND", "tool update policy"),
                ("setup_lts.x", "setup_24.x", "tool update policy"),
                ("npm@latest", "npm@12.0.2", "tool update policy"),
            ]:
                with self.subTest(template=path.parent.name, change=new):
                    self.reject_change(relative, old, new, message)

    def test_every_template_rejects_rtk_installation(self) -> None:
        for path in sorted((self.root / "templates").glob("*/Dockerfile")):
            relative = str(path.relative_to(self.root))
            for instruction in [
                "RUN curl -fsSL https://github.com/rtk-ai/rtk/releases/latest/download/rtk.tar.gz",
                "COPY rtk /usr/local/bin/rtk",
                "RUN npm install -g rtk",
            ]:
                with self.subTest(template=path.parent.name, instruction=instruction):
                    self.reject_change(relative, "ENV DEBIAN_FRONTEND",
                                       instruction + "\nENV DEBIAN_FRONTEND",
                                       "RTK must not be installed")

    def test_codex_floats_without_losing_cli_checks(self) -> None:
        for template in ["pi", "codex", "codex-ollama", "remote-dev"]:
            relative = f"templates/{template}/Dockerfile"
            for old, new, message in [
                ("@openai/codex@latest", "@openai/codex@0.153.3", "tool update policy"),
                ("codex exec --help", "true", "codex exec --help"),
                ("codex app-server --help", "true", "codex app-server --help"),
            ]:
                with self.subTest(template=template, change=new):
                    self.reject_change(relative, old, new, message)

    def test_uv_must_float_outside_home(self) -> None:
        for replacement in ["uv:0.11.11", "uv:latest@sha256:" + "a" * 64]:
            with self.subTest(replacement=replacement):
                self.reject_change("templates/pi/Dockerfile", "uv:latest", replacement,
                                   "floating uv/uvx")
        self.reject_change("templates/pi/Dockerfile", "/uv /uvx /usr/local/bin/",
                           "/uv /uvx /home/agent/.local/bin/", "floating uv/uvx")

    def test_rebuild_refreshes_layers_and_external_images(self) -> None:
        for flag in ["--no-cache", "--pull"]:
            with self.subTest(flag=flag):
                self.reject_change("justfile", "build --no-cache --pull",
                                   "build " + ("--pull" if flag == "--no-cache" else "--no-cache"),
                                   "uncached rebuild")

    def test_upstream_hermes_locks_remain_required(self) -> None:
        for old in ["--locked", "npm ci --no-audit --no-fund"]:
            with self.subTest(old=old):
                self.reject_change("templates/hermes/Dockerfile", old, "", old)

    def test_unrelated_mount_guard_still_rejects_unsafe_change(self) -> None:
        self.reject_change("templates/pi/compose.yml", "create_host_path: false",
                           "create_host_path: true", "create_host_path: false")


if __name__ == "__main__":
    unittest.main()
