#!/usr/bin/env python3
"""Validate the sannux documentation/template contract.

This is a structural check. It intentionally avoids validating user-specific
values such as model names, endpoints, or real workspace paths.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class ContractCheck:
    def __init__(self, root: Path) -> None:
        self.root = root
        self.errors: list[str] = []

    def path(self, relative: str) -> Path:
        return self.root / relative

    def read(self, relative: str) -> str:
        file_path = self.path(relative)
        if not file_path.is_file():
            self.fail(relative, "file is missing")
            return ""
        return file_path.read_text(encoding="utf-8")

    def fail(self, relative: str, message: str) -> None:
        self.errors.append(f"{relative}: {message}")

    def require_contains(
        self, relative: str, text: str, needle: str, description: str
    ) -> None:
        if needle not in text:
            self.fail(relative, f"missing {description}: {needle!r}")

    def require_regex(
        self, relative: str, text: str, pattern: str, description: str
    ) -> None:
        if not re.search(pattern, text, flags=re.MULTILINE | re.DOTALL):
            self.fail(relative, f"missing {description}")

    def require_terms(self, relative: str, text: str, terms: list[str]) -> None:
        lowered = re.sub(r"\s+", " ", text.lower())
        for term in terms:
            normalized_term = re.sub(r"\s+", " ", term.lower())
            if normalized_term not in lowered:
                self.fail(relative, f"missing required contract term: {term}")

    def require_heading_terms(
        self, relative: str, text: str, heading_terms: list[str]
    ) -> None:
        headings = [
            line.lstrip("#").strip().lower()
            for line in text.splitlines()
            if line.startswith("#")
        ]
        for term in heading_terms:
            normalized_term = term.lower()
            if not any(normalized_term in heading for heading in headings):
                self.fail(relative, f"missing required heading containing: {term}")

    def check_contract_doc(self) -> None:
        relative = "docs/template-contract.md"
        text = self.read(relative)
        if not text:
            return

        for heading in [
            "# Sannux Template Contract",
            "## Core Concepts",
            "## Template Contract",
            "## Config Contract",
            "## Run Modes",
            "## Exceptions",
            "## Validation",
        ]:
            self.require_contains(relative, text, heading, "contract heading")

        self.require_terms(
            relative,
            text,
            [
                "Template",
                "Initial persistent config",
                "Run",
                "Agent home",
                "Persistent agent",
                "Ephemeral run",
                "Daemon service",
                "Compose profile",
                "just check",
                "must not validate user-specific values",
            ],
        )

    def check_root_readmes(self) -> None:
        checks = [
            (
                "README.md",
                "## Core concepts",
                [
                    "Template",
                    "Initial persistent config",
                    "Run",
                    "Agent home",
                    "Persistent",
                    "Ephemeral",
                    "Daemon",
                ],
            ),
            (
                "README-PT-BR.md",
                "## Conceitos centrais",
                [
                    "Template",
                    "Config inicial persistente",
                    "Run",
                    "Agent home",
                    "persistente",
                    "efêmero",
                    "daemon",
                ],
            ),
        ]
        for relative, heading, terms in checks:
            text = self.read(relative)
            if not text:
                continue
            self.require_contains(relative, text, heading, "core concepts heading")
            self.require_contains(
                relative,
                text,
                "docs/template-contract.md",
                "link to template contract",
            )
            self.require_terms(relative, text, terms)

    def check_agent_guides(self) -> None:
        for relative in ["AGENTS.md", "CLAUDE.md"]:
            text = self.read(relative)
            if not text:
                continue
            self.require_contains(
                relative,
                text,
                "docs/template-contract.md",
                "rule to consult the template contract",
            )
            self.require_contains(relative, text, "just check", "contract check")
            self.require_contains(
                relative,
                text,
                "templates/<template>",
                "template placeholder terminology",
            )

    def check_codex_readmes(self) -> None:
        checks = [
            (
                "templates/codex/README.md",
                [
                    "setup",
                    "scenarios",
                    "persistent TUI",
                    "one-shot",
                    "ephemeral home",
                    "what not to mount",
                ],
            ),
            (
                "templates/codex/README-PT-BR.md",
                [
                    "setup",
                    "cenários",
                    "TUI persistente",
                    "one-shot",
                    "home efêmera",
                    "o que não montar",
                ],
            ),
        ]
        required_terms = [
            "Docker Compose",
            "just",
            ".codex",
            "OPENAI_API_KEY",
            "--dangerously-bypass-approvals-and-sandbox",
        ]
        for relative, required_headings in checks:
            text = self.read(relative)
            if not text:
                continue
            self.require_heading_terms(relative, text, required_headings)
            self.require_terms(relative, text, required_terms)

    def check_codex_compose(self) -> None:
        relative = "templates/codex/compose.yml"
        text = self.read(relative)
        if not text:
            return

        self.require_regex(
            relative,
            text,
            r"source:\s*\n\s*\$\{WORKSPACE_PATH:[\s\S]*?target:\s*/workspace"
            r"[\s\S]*?bind:\s*\n\s*create_host_path:\s*false",
            "WORKSPACE_PATH bind mount guarded by create_host_path: false",
        )
        self.require_regex(
            relative,
            text,
            r"source:\s*\n\s*\$\{AGENT_HOME_PATH:[\s\S]*?target:\s*/home/agent"
            r"[\s\S]*?bind:\s*\n\s*create_host_path:\s*false",
            "AGENT_HOME_PATH bind mount guarded by create_host_path: false",
        )

    def check_codex_env_example(self) -> None:
        relative = "templates/codex/.env.example"
        text = self.read(relative)
        if not text:
            return

        for key in ["WORKSPACE_PATH", "AGENT_HOME_PATH"]:
            self.require_regex(
                relative,
                text,
                rf"^{key}=$",
                f"{key} present and intentionally blank",
            )

    def check_codex_setup_script(self) -> None:
        relative = "templates/codex/setup-host.sh"
        script_path = self.path(relative)
        if not script_path.is_file():
            self.fail(relative, "file is missing")
            return
        if not os.access(script_path, os.X_OK):
            self.fail(relative, "setup script is not executable")

    def check_codex_ollama_readmes(self) -> None:
        checks = [
            (
                "templates/codex-ollama/README.md",
                [
                    "setup",
                    "scenarios",
                    "persistent TUI",
                    "one-shot",
                    "ephemeral home",
                    "what not to mount",
                ],
            ),
            (
                "templates/codex-ollama/README-PT-BR.md",
                [
                    "setup",
                    "cenários",
                    "TUI persistente",
                    "one-shot",
                    "home efêmera",
                    "o que não montar",
                ],
            ),
        ]
        required_terms = ["Docker Compose", "just", ".codex"]
        for relative, required_headings in checks:
            text = self.read(relative)
            if not text:
                continue
            self.require_heading_terms(relative, text, required_headings)
            self.require_terms(relative, text, required_terms)

    def check_codex_ollama_compose(self) -> None:
        relative = "templates/codex-ollama/compose.yml"
        text = self.read(relative)
        if not text:
            return

        self.require_regex(
            relative,
            text,
            r"source:\s*\n\s*\$\{WORKSPACE_PATH:[\s\S]*?target:\s*/workspace"
            r"[\s\S]*?bind:\s*\n\s*create_host_path:\s*false",
            "WORKSPACE_PATH bind mount guarded by create_host_path: false",
        )
        self.require_regex(
            relative,
            text,
            r"source:\s*\n\s*\$\{AGENT_HOME_PATH:[\s\S]*?target:\s*/home/agent"
            r"[\s\S]*?bind:\s*\n\s*create_host_path:\s*false",
            "AGENT_HOME_PATH bind mount guarded by create_host_path: false",
        )

    def check_codex_ollama_env_example(self) -> None:
        relative = "templates/codex-ollama/.env.example"
        text = self.read(relative)
        if not text:
            return

        for key in ["WORKSPACE_PATH", "AGENT_HOME_PATH"]:
            self.require_regex(
                relative,
                text,
                rf"^{key}=$",
                f"{key} present and intentionally blank",
            )

    def check_claude_ollama_readmes(self) -> None:
        checks = [
            (
                "templates/claude-ollama/README.md",
                [
                    "setup",
                    "scenarios",
                    "persistent TUI",
                    "one-shot",
                    "ephemeral home",
                    "what not to mount",
                ],
            ),
            (
                "templates/claude-ollama/README-PT-BR.md",
                [
                    "setup",
                    "cenários",
                    "TUI persistente",
                    "one-shot",
                    "home efêmera",
                    "o que não montar",
                ],
            ),
        ]
        required_terms = [
            "Docker Compose",
            "just",
            "ANTHROPIC_BASE_URL",
            "--no-session-persistence",
        ]
        for relative, required_headings in checks:
            text = self.read(relative)
            if not text:
                continue
            self.require_heading_terms(relative, text, required_headings)
            self.require_terms(relative, text, required_terms)

    def check_claude_ollama_compose(self) -> None:
        relative = "templates/claude-ollama/compose.yml"
        text = self.read(relative)
        if not text:
            return

        self.require_regex(
            relative,
            text,
            r"source:\s*\n\s*\$\{WORKSPACE_PATH:[\s\S]*?target:\s*/workspace"
            r"[\s\S]*?bind:\s*\n\s*create_host_path:\s*false",
            "WORKSPACE_PATH bind mount guarded by create_host_path: false",
        )
        self.require_regex(
            relative,
            text,
            r"source:\s*\n\s*\$\{AGENT_HOME_PATH:[\s\S]*?target:\s*/home/agent"
            r"[\s\S]*?bind:\s*\n\s*create_host_path:\s*false",
            "AGENT_HOME_PATH bind mount guarded by create_host_path: false",
        )

    def check_claude_ollama_env_example(self) -> None:
        relative = "templates/claude-ollama/.env.example"
        text = self.read(relative)
        if not text:
            return

        for key in ["WORKSPACE_PATH", "AGENT_HOME_PATH"]:
            self.require_regex(
                relative,
                text,
                rf"^{key}=$",
                f"{key} present and intentionally blank",
            )

    def check_claude_ollama_setup_script(self) -> None:
        relative = "templates/claude-ollama/setup-host.sh"
        script_path = self.path(relative)
        if not script_path.is_file():
            self.fail(relative, "file is missing")
            return
        if not os.access(script_path, os.X_OK):
            self.fail(relative, "setup script is not executable")

    def check_claude_code_readmes(self) -> None:
        checks = [
            (
                "templates/claude-code/README.md",
                [
                    "setup",
                    "scenarios",
                    "persistent TUI",
                    "daemon",
                    "one-shot",
                    "ephemeral home",
                    "what not to mount",
                ],
            ),
            (
                "templates/claude-code/README-PT-BR.md",
                [
                    "setup",
                    "cenários",
                    "TUI persistente",
                    "daemon",
                    "one-shot",
                    "home efêmera",
                    "o que não montar",
                ],
            ),
        ]
        required_terms = [
            "Docker Compose",
            "just",
            ".claude",
            ".claude.json",
            "remote-control",
            "--no-session-persistence",
            "--dangerously-skip-permissions",
        ]
        for relative, required_headings in checks:
            text = self.read(relative)
            if not text:
                continue
            self.require_heading_terms(relative, text, required_headings)
            self.require_terms(relative, text, required_terms)

    def check_claude_code_compose(self) -> None:
        relative = "templates/claude-code/compose.yml"
        text = self.read(relative)
        if not text:
            return

        self.require_regex(
            relative,
            text,
            r"source:\s*\n\s*\$\{WORKSPACE_PATH:[\s\S]*?target:\s*/workspace"
            r"[\s\S]*?bind:\s*\n\s*create_host_path:\s*false",
            "WORKSPACE_PATH bind mount guarded by create_host_path: false",
        )
        self.require_regex(
            relative,
            text,
            r"source:\s*\n\s*\$\{AGENT_HOME_PATH:[\s\S]*?target:\s*/home/agent"
            r"[\s\S]*?bind:\s*\n\s*create_host_path:\s*false",
            "AGENT_HOME_PATH bind mount guarded by create_host_path: false",
        )
        self.require_terms(relative, text, ["profiles: ['daemon']", "remote-control"])

    def check_claude_code_env_example(self) -> None:
        relative = "templates/claude-code/.env.example"
        text = self.read(relative)
        if not text:
            return

        for key in ["WORKSPACE_PATH", "AGENT_HOME_PATH"]:
            self.require_regex(
                relative,
                text,
                rf"^{key}=$",
                f"{key} present and intentionally blank",
            )

    def check_claude_code_setup_script(self) -> None:
        relative = "templates/claude-code/setup-host.sh"
        script_path = self.path(relative)
        if not script_path.is_file():
            self.fail(relative, "file is missing")
            return
        if not os.access(script_path, os.X_OK):
            self.fail(relative, "setup script is not executable")

    def check_hermes_readmes(self) -> None:
        checks = [
            (
                "templates/hermes/README.md",
                [
                    "setup",
                    "scenarios",
                    "persistent TUI",
                    "daemon",
                    "one-shot",
                    "ephemeral home",
                    "what not to mount",
                ],
            ),
            (
                "templates/hermes/README-PT-BR.md",
                [
                    "setup",
                    "cenários",
                    "TUI persistente",
                    "daemon",
                    "one-shot",
                    "home efêmera",
                    "o que não montar",
                ],
            ),
        ]
        required_terms = [
            "Docker Compose",
            "just",
            ".hermes",
            "gateway",
            "gateway run",
            "dashboard",
            "--skip-build",
            "--accept-hooks",
            "-z",
        ]
        for relative, required_headings in checks:
            text = self.read(relative)
            if not text:
                continue
            self.require_heading_terms(relative, text, required_headings)
            self.require_terms(relative, text, required_terms)

    def check_hermes_compose(self) -> None:
        relative = "templates/hermes/compose.yml"
        text = self.read(relative)
        if not text:
            return

        self.require_regex(
            relative,
            text,
            r"source:\s*\n\s*\$\{WORKSPACE_PATH:[\s\S]*?target:\s*/workspace"
            r"[\s\S]*?bind:\s*\n\s*create_host_path:\s*false",
            "WORKSPACE_PATH bind mount guarded by create_host_path: false",
        )
        self.require_regex(
            relative,
            text,
            r"source:\s*\n\s*\$\{AGENT_HOME_PATH:[\s\S]*?target:\s*/home/agent"
            r"[\s\S]*?bind:\s*\n\s*create_host_path:\s*false",
            "AGENT_HOME_PATH bind mount guarded by create_host_path: false",
        )
        self.require_terms(
            relative,
            text,
            ["profiles: ['daemon']", "gateway", "dashboard", "HOST_PORT_DASHBOARD"],
        )

    def check_hermes_env_example(self) -> None:
        relative = "templates/hermes/.env.example"
        text = self.read(relative)
        if not text:
            return

        for key in ["WORKSPACE_PATH", "AGENT_HOME_PATH"]:
            self.require_regex(
                relative,
                text,
                rf"^{key}=$",
                f"{key} present and intentionally blank",
            )
        self.require_contains(
            relative,
            text,
            "HOST_PORT_DASHBOARD=9119",
            "dashboard host port default",
        )

    def check_hermes_setup_script(self) -> None:
        relative = "templates/hermes/setup-host.sh"
        script_path = self.path(relative)
        if not script_path.is_file():
            self.fail(relative, "file is missing")
            return
        if not os.access(script_path, os.X_OK):
            self.fail(relative, "setup script is not executable")

    def check_gemini_readmes(self) -> None:
        checks = [
            (
                "templates/gemini/README.md",
                [
                    "setup",
                    "scenarios",
                    "persistent TUI",
                    "daemon",
                    "one-shot",
                    "ephemeral home",
                    "what not to mount",
                ],
            ),
            (
                "templates/gemini/README-PT-BR.md",
                [
                    "setup",
                    "cenários",
                    "TUI persistente",
                    "daemon",
                    "one-shot",
                    "home efêmera",
                    "o que não montar",
                ],
            ),
        ]
        required_terms = [
            "Docker Compose",
            "just",
            ".gemini",
            "GEMINI_API_KEY",
            "--prompt",
            "--approval-mode",
            "--yolo",
        ]
        for relative, required_headings in checks:
            text = self.read(relative)
            if not text:
                continue
            self.require_heading_terms(relative, text, required_headings)
            self.require_terms(relative, text, required_terms)

    def check_gemini_compose(self) -> None:
        relative = "templates/gemini/compose.yml"
        text = self.read(relative)
        if not text:
            return

        self.require_regex(
            relative,
            text,
            r"source:\s*\n\s*\$\{WORKSPACE_PATH:[\s\S]*?target:\s*/workspace"
            r"[\s\S]*?bind:\s*\n\s*create_host_path:\s*false",
            "WORKSPACE_PATH bind mount guarded by create_host_path: false",
        )
        self.require_regex(
            relative,
            text,
            r"source:\s*\n\s*\$\{AGENT_HOME_PATH:[\s\S]*?target:\s*/home/agent"
            r"[\s\S]*?bind:\s*\n\s*create_host_path:\s*false",
            "AGENT_HOME_PATH bind mount guarded by create_host_path: false",
        )

    def check_gemini_env_example(self) -> None:
        relative = "templates/gemini/.env.example"
        text = self.read(relative)
        if not text:
            return

        for key in ["WORKSPACE_PATH", "AGENT_HOME_PATH"]:
            self.require_regex(
                relative,
                text,
                rf"^{key}=$",
                f"{key} present and intentionally blank",
            )

    def check_gemini_setup_script(self) -> None:
        relative = "templates/gemini/setup-host.sh"
        script_path = self.path(relative)
        if not script_path.is_file():
            self.fail(relative, "file is missing")
            return
        if not os.access(script_path, os.X_OK):
            self.fail(relative, "setup script is not executable")

    def check_opencode_readmes(self) -> None:
        checks = [
            (
                "templates/opencode/README.md",
                [
                    "setup",
                    "scenarios",
                    "persistent TUI",
                    "daemon",
                    "one-shot",
                    "ephemeral home",
                    "what not to mount",
                ],
            ),
            (
                "templates/opencode/README-PT-BR.md",
                [
                    "setup",
                    "cenários",
                    "TUI persistente",
                    "daemon",
                    "one-shot",
                    "home efêmera",
                    "o que não montar",
                ],
            ),
        ]
        required_terms = [
            "Docker Compose",
            "just",
            ".config/opencode",
            ".local/share/opencode",
            "auth.json",
            "OPENAI_API_KEY",
            "opencode run",
            "permission",
            "--dangerously-skip-permissions",
        ]
        for relative, required_headings in checks:
            text = self.read(relative)
            if not text:
                continue
            self.require_heading_terms(relative, text, required_headings)
            self.require_terms(relative, text, required_terms)

    def check_opencode_compose(self) -> None:
        relative = "templates/opencode/compose.yml"
        text = self.read(relative)
        if not text:
            return

        self.require_regex(
            relative,
            text,
            r"source:\s*\n\s*\$\{WORKSPACE_PATH:[\s\S]*?target:\s*/workspace"
            r"[\s\S]*?bind:\s*\n\s*create_host_path:\s*false",
            "WORKSPACE_PATH bind mount guarded by create_host_path: false",
        )
        self.require_regex(
            relative,
            text,
            r"source:\s*\n\s*\$\{AGENT_HOME_PATH:[\s\S]*?target:\s*/home/agent"
            r"[\s\S]*?bind:\s*\n\s*create_host_path:\s*false",
            "AGENT_HOME_PATH bind mount guarded by create_host_path: false",
        )

    def check_opencode_env_example(self) -> None:
        relative = "templates/opencode/.env.example"
        text = self.read(relative)
        if not text:
            return

        for key in ["WORKSPACE_PATH", "AGENT_HOME_PATH"]:
            self.require_regex(
                relative,
                text,
                rf"^{key}=$",
                f"{key} present and intentionally blank",
            )

    def check_opencode_setup_script(self) -> None:
        relative = "templates/opencode/setup-host.sh"
        script_path = self.path(relative)
        if not script_path.is_file():
            self.fail(relative, "file is missing")
            return
        if not os.access(script_path, os.X_OK):
            self.fail(relative, "setup script is not executable")

    def check_pi_readmes(self) -> None:
        checks = [
            (
                "templates/pi/README.md",
                [
                    "setup",
                    "scenarios",
                    "persistent TUI",
                    "daemon",
                    "one-shot",
                    "ephemeral home",
                    "what not to mount",
                ],
            ),
            (
                "templates/pi/README-PT-BR.md",
                [
                    "setup",
                    "cenários",
                    "TUI persistente",
                    "daemon",
                    "one-shot",
                    "home efêmera",
                    "o que não montar",
                ],
            ),
        ]
        required_terms = [
            "Docker Compose",
            "just",
            ".pi/agent",
            "auth.json",
            "settings.json",
            "models.json",
            "--print",
            "--no-session",
            "--tools read,grep,find,ls",
        ]
        for relative, required_headings in checks:
            text = self.read(relative)
            if not text:
                continue
            self.require_heading_terms(relative, text, required_headings)
            self.require_terms(relative, text, required_terms)

    def check_pi_compose(self) -> None:
        relative = "templates/pi/compose.yml"
        text = self.read(relative)
        if not text:
            return

        self.require_regex(
            relative,
            text,
            r"source:\s*\n\s*\$\{WORKSPACE_PATH:[\s\S]*?target:\s*/workspace"
            r"[\s\S]*?bind:\s*\n\s*create_host_path:\s*false",
            "WORKSPACE_PATH bind mount guarded by create_host_path: false",
        )
        self.require_regex(
            relative,
            text,
            r"source:\s*\n\s*\$\{AGENT_HOME_PATH:[\s\S]*?target:\s*/home/agent"
            r"[\s\S]*?bind:\s*\n\s*create_host_path:\s*false",
            "AGENT_HOME_PATH bind mount guarded by create_host_path: false",
        )

    def check_pi_env_example(self) -> None:
        relative = "templates/pi/.env.example"
        text = self.read(relative)
        if not text:
            return

        for key in ["WORKSPACE_PATH", "AGENT_HOME_PATH"]:
            self.require_regex(
                relative,
                text,
                rf"^{key}=$",
                f"{key} present and intentionally blank",
            )
        self.require_contains(
            relative,
            text,
            "PI_CODING_AGENT_DIR=/home/agent/.pi/agent",
            "Pi config dir override",
        )

    def check_pi_setup_script(self) -> None:
        relative = "templates/pi/setup-host.sh"
        script_path = self.path(relative)
        if not script_path.is_file():
            self.fail(relative, "file is missing")
            return
        if not os.access(script_path, os.X_OK):
            self.fail(relative, "setup script is not executable")

    def check_remote_dev_readmes(self) -> None:
        checks = [
            (
                "templates/remote-dev/README.md",
                [
                    "setup",
                    "scenarios",
                    "persistent TUI",
                    "daemon",
                    "one-shot",
                    "ephemeral home",
                    "what not to mount",
                ],
            ),
            (
                "templates/remote-dev/README-PT-BR.md",
                [
                    "setup",
                    "cenários",
                    "TUI persistente",
                    "daemon",
                    "one-shot",
                    "home efêmera",
                    "o que não montar",
                ],
            ),
        ]
        required_terms = [
            "Docker Compose",
            "just",
            "Remote SSH",
            "sannux-remote-dev",
            "app-server-control",
            "daemon",
            "not a harness",
        ]
        required_terms_pt = [
            "Docker Compose",
            "just",
            "Remote SSH",
            "sannux-remote-dev",
            "app-server-control",
            "daemon",
            "não é um harness",
        ]
        for relative, required_headings in checks:
            text = self.read(relative)
            if not text:
                continue
            self.require_heading_terms(relative, text, required_headings)
            terms = required_terms_pt if relative.endswith("PT-BR.md") else required_terms
            self.require_terms(relative, text, terms)

    def check_remote_dev_compose(self) -> None:
        relative = "templates/remote-dev/compose.yml"
        text = self.read(relative)
        if not text:
            return

        self.require_regex(
            relative,
            text,
            r"source:\s*\n\s*\$\{WORKSPACE_PATH:[\s\S]*?target:\s*/workspace"
            r"[\s\S]*?bind:\s*\n\s*create_host_path:\s*false",
            "WORKSPACE_PATH bind mount guarded by create_host_path: false",
        )
        self.require_regex(
            relative,
            text,
            r"source:\s*\n\s*\$\{AGENT_HOME_PATH:[\s\S]*?target:\s*/home/\$\{REMOTE_USER:-agent\}"
            r"[\s\S]*?bind:\s*\n\s*create_host_path:\s*false",
            "AGENT_HOME_PATH bind mount guarded by create_host_path: false",
        )
        self.require_terms(
            relative,
            text,
            [
                "profiles: ['daemon']",
                "ssh",
                "agent",
                "HOST_SSH_PORT",
                "HOST_PORT_3000",
                "app-server-control",
            ],
        )

    def check_remote_dev_env_example(self) -> None:
        relative = "templates/remote-dev/.env.example"
        text = self.read(relative)
        if not text:
            return

        for key in ["WORKSPACE_PATH", "AGENT_HOME_PATH"]:
            self.require_regex(
                relative,
                text,
                rf"^{key}=$",
                f"{key} present and intentionally blank",
            )
        self.require_contains(
            relative,
            text,
            "SSH_BIND_ADDRESS=127.0.0.1",
            "local SSH bind default",
        )
        self.require_contains(
            relative,
            text,
            "SSH_HOST_ALIAS=sannux-remote-dev",
            "SSH host alias default",
        )

    def check_remote_dev_setup_script(self) -> None:
        relative = "templates/remote-dev/setup-host.sh"
        script_path = self.path(relative)
        if not script_path.is_file():
            self.fail(relative, "file is missing")
            return
        if not os.access(script_path, os.X_OK):
            self.fail(relative, "setup script is not executable")

        text = self.read(relative)
        self.require_terms(
            relative,
            text,
            [
                "require_absolute_path",
                "reject_unsafe_path",
                "docker compose build",
                "docker compose --profile daemon up -d ssh",
                "ssh-keygen",
                "prune_known_host",
                "authorized_keys",
                "sandbox_mode",
            ],
        )

    def run(self) -> int:
        self.check_contract_doc()
        self.check_root_readmes()
        self.check_agent_guides()
        self.check_codex_readmes()
        self.check_codex_compose()
        self.check_codex_env_example()
        self.check_codex_setup_script()
        self.check_codex_ollama_readmes()
        self.check_codex_ollama_compose()
        self.check_codex_ollama_env_example()
        self.check_claude_ollama_readmes()
        self.check_claude_ollama_compose()
        self.check_claude_ollama_env_example()
        self.check_claude_ollama_setup_script()
        self.check_claude_code_readmes()
        self.check_claude_code_compose()
        self.check_claude_code_env_example()
        self.check_claude_code_setup_script()
        self.check_gemini_readmes()
        self.check_gemini_compose()
        self.check_gemini_env_example()
        self.check_gemini_setup_script()
        self.check_opencode_readmes()
        self.check_opencode_compose()
        self.check_opencode_env_example()
        self.check_opencode_setup_script()
        self.check_pi_readmes()
        self.check_pi_compose()
        self.check_pi_env_example()
        self.check_pi_setup_script()
        self.check_hermes_readmes()
        self.check_hermes_compose()
        self.check_hermes_env_example()
        self.check_hermes_setup_script()
        self.check_remote_dev_readmes()
        self.check_remote_dev_compose()
        self.check_remote_dev_env_example()
        self.check_remote_dev_setup_script()

        if self.errors:
            print("sannux contract check failed:", file=sys.stderr)
            for error in self.errors:
                print(f"- {error}", file=sys.stderr)
            return 1

        print("sannux contract check passed")
        return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        type=Path,
        default=ROOT,
        help="Repository root to validate (defaults to this checkout).",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    return ContractCheck(args.root.resolve()).run()


if __name__ == "__main__":
    raise SystemExit(main())
