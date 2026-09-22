#!/usr/bin/env python3
"""Exercise setup with an isolated home and synthetic Ollama configuration."""

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import tomllib

ROOT = Path(__file__).resolve().parents[1]


class CodexConfigTest(unittest.TestCase):
    def test_setup_preserves_provider_without_ignored_settings(self):
        with tempfile.TemporaryDirectory(prefix="sannux-config-") as directory:
            root = Path(directory)
            template = root / "template"
            template.mkdir()
            for name in ("setup-host.sh", "codex-config.toml.template"):
                shutil.copy2(ROOT / "templates/codex-ollama" / name, template)
            home = root / "agent-home"
            (template / ".env").write_text(
                f"WORKSPACE_PATH={root / 'workspace'}\n"
                f"AGENT_HOME_PATH={home}\n"
                "OLLAMA_BASE_URL=http://127.0.0.1:11434/v1\n"
                "CODEX_MODEL=fixture-model:8b\n"
                "CODEX_MODEL_PROVIDER=fixture_provider\n"
                "CODEX_PROFILE=fixture_profile\n"
            )
            result = subprocess.run(
                ["bash", str(template / "setup-host.sh")],
                env={**os.environ, "HOME": str(root)},
                capture_output=True,
                check=False,
                text=True,
                timeout=20,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            path = home / ".codex/config.toml"
            config = tomllib.loads(path.read_text())
            self.assertNotIn("base_url", config)
            self.assertNotIn("remote_connections", config["features"])
            for profile in config["profiles"].values():
                for ignored in ("base_url", "openai_base_url", "forced_login_method"):
                    self.assertNotIn(ignored, profile)
            provider = config["model_providers"]["fixture_provider"]
            self.assertEqual(provider["base_url"], "http://127.0.0.1:11434/v1")
            self.assertEqual(provider["wire_api"], "responses")
            self.assertEqual(config["model_provider"], "fixture_provider")
            profile = config["profiles"]["fixture_profile"]
            self.assertEqual(profile["model_provider"], "fixture_provider")
            self.assertEqual(profile["model"], "fixture-model:8b")
            self.assertEqual(config["approval_policy"], "never")
            self.assertEqual(config["sandbox_mode"], "danger-full-access")
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()
