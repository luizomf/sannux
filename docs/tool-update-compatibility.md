# Floating tool compatibility audit

Owner-authorized policy change: [sannux #28](https://github.com/luizomf/sannux/issues/28).
[Português](tool-update-compatibility-PT-BR.md).

Only the Debian base stays pinned. This audit records observations, not new
version requirements. See the [contract](template-contract.md) and
[maintenance checklist](../AGENTS.md#shared-runtime-maintenance-checklist).

## Inventory and decisions

| Surface | Finding and decision |
| --- | --- |
| All ten Dockerfiles | Removed repository RTK version/SHA constants and exact npm version; replaced NodeSource numeric majors with `setup_lts.x`. All ten Debian FROM lines are byte-for-byte unchanged. |
| RTK | Latest resolves once to a validated release tag. Download both archive and `checksums.txt` from that tag, require exactly one matching checksum, verify before extraction and compare executable version to the resolved tag. Linux amd64 musl and arm64 GNU artifact names and the `rtk` archive member remain supported. Missing assets/checksums fail closed. |
| Node/npm | Official [NodeSource LTS channel](https://deb.nodesource.com/setup_lts.x), then `npm@latest` with `--engine-strict`. At validation, Node 24.20.0 satisfied npm 12.0.2's `^22.22.2 || ^24.15.0 || >=26.0.0` engine range. No numeric Node major is selected by sannux. |
| Codex | All four consumers install npm latest and check version, exec and app-server interfaces. [PR #26](https://github.com/luizomf/sannux/pull/26) documented account-specific catalog differences between 0.151.0 and 0.153.3; it did not establish a need to remain on exactly 0.153.3. The old exact assertions contradicted the owner's rebuild policy and already failed at baseline. Replaced with floating-policy regressions and offline CLI checks, not a claim about account availability. |
| Codex config/catalog | Inspected setup rendering, TOML and shipped JSON. Current [0.153.4 protocol source](https://github.com/openai/codex/blob/rust-v0.153.4/codex-rs/protocol/src/openai_models.rs) still accepts `shell_command` as a shell alias and promotes legacy `base_instructions` through the ModelsResponse adapter. Required metadata is present. Some legacy flags no longer correspond to ModelInfo fields; do not assume they control current behavior. Catalog/config remain unchanged: model IDs, enums, context limits and `/v1` are not software pins. No model listing or generation was performed. |
| uv | Pi now copies official `uv:latest` binaries into `/usr/local/bin`. Existing offline smoke checks paths, non-root execution and actual venv/run behavior, not an exact version. Latest manifest has linux/amd64 and linux/arm64. |
| Hermes | Existing upstream `main` installer remains floating. Its [pyproject](https://github.com/NousResearch/hermes-agent/blob/main/pyproject.toml) requires Python `>=3.11,<3.14` and has deliberate dependency pins/aging rules; the installer currently selects Python 3.11. Root [package.json](https://github.com/NousResearch/hermes-agent/blob/main/package.json) requires Node `^22.22.0 || ^24.11.0 || >=26.0.0`, npm `<11.10.0 || >=11.17.0`. [PR #16](https://github.com/luizomf/sannux/pull/16) explains the older bundled-npm failure. Preserve upstream uv/npm locks, engine-strict and installer runtime choices; do not rewrite upstream dependencies. `uv sync --locked` and `npm ci` stay. |
| Other CLIs/installers | Gemini, Claude/Ollama, OpenCode, Pi and playwright-core already use floating npm distributions. Gemini's vendor ripgrep compatibility link remains unchanged. Antigravity now installs through its official SHA512-verifying installer at image build into `/usr/local/bin`; Claude Code uses the official stable installer and copies the native binary there. Both work without a home-installed executable. Intentional home PATH overrides remain possible. |
| Scripts/consumers | `just rebuild` now uses `--no-cache --pull`; normal build remains cached. `scripts/rebuild_all_templates` inherits this recipe, but also calls setup (remote-dev setup starts SSH): inspected, not executed as a harmless build-only command. Setup scripts, Compose wiring and browser-fetch implementations were inspected and left unchanged apart from the two native CLI entrypoints. No tracked extension snapshot or dependency lockfile exists in sannux. Mounted extensions, inbox and separate Daily consumers were not loaded or modified. |

Dockerfile syntax version, schema/protocol versions, model examples, ports and
UID/GID defaults were not treated as pins. Debian packages remain constrained by
the selected Debian distribution's repositories, not individual upstream latest.

## Actual validation

- Baseline `just check`: failed on three stale Pi Codex pin requirements.
- New cross-template policy guard: RED on all ten Dockerfiles, then GREEN.
  Literal RTK tag bypass test also failed before its guard and passed afterward.
- `just check` now runs the original structural/security suite plus eight policy
  regression tests, including per-template mutations for RTK/npm/Node pins,
  lost checksum/architecture checks, Codex pins/CLI checks, uv placement/digests,
  rebuild flags, Hermes locks and an unsafe mount guard change.
- All ten Compose files: minimal synthetic subprocess environment,
  `--env-file /dev/null`, all profiles, `config --no-env-resolution --format json`.
  Asserted build contexts/default UID, workspace/home targets and bind guards;
  missing required paths rejected. No real `.env` loaded or printed.
- Pi: actual `docker build --no-cache --pull`, candidate `sannux/pi:policy-28`,
  linux/arm64. Node 24.20.0, npm 12.0.2, RTK 0.48.0, Pi 0.85.1,
  Codex 0.153.4, uv/uvx 0.12.10. `check-uv.sh` and `check-tools.sh` passed
  non-root, empty replacement home, read-only root, no external network or host
  mounts. Checks include uv venv/run, Node package engines, RTK proxy,
  Pi/Codex CLI flags, native esbuild TypeScript transform and browser-fetch's
  actual JavaScript-rendered loopback fixture with Debian Chromium/playwright.
- Public npm metadata: Gemini 0.58.0 and playwright-core 1.63.0 require Node
  `>=20`; Claude Code npm 2.1.263 requires `>=22.0.0`; OpenCode 1.18.29 declares
  no Node engine. These metadata checks do not replace template runtime tests.
- npm reported blocked dependency install scripts; esbuild's shipped native
  binary passed the transform test. No blanket script allowance was added.
- Antigravity and Claude: actual candidate builds reused the newly built common
  layers; fresh-home offline non-root entrypoints passed: agy 1.1.27 and Claude
  2.1.236. Tags: `sannux/agy:policy-28`, `sannux/claude-code:policy-28`.
  Synthetic home CLI overrides also verified literal argument and stdin forwarding
  through both entrypoints, without invoking a model.
- Codex: generated config using the actual setup script in an isolated container;
  app-server initialize + `config/read` accepted the synthetic provider/model.
  No model/provider requests; catalog schema inspection is source-level, not a
  live catalog or model-behavior test.
- Hermes source `22c5684b983eac6a81ee015ae80296c4b3dbf5bb`: in a disposable
  credential-free Pi candidate, `uv sync --locked --dry-run --extra all
  --extra messaging --python /usr/bin/python3` and `npm ci --dry-run
  --ignore-scripts --no-audit --no-fund` from `web` passed. This checks resolution
  and engine/lock compatibility, not a full Hermes build/dashboard/runtime.
- Both RTK Linux archives downloaded and checked against their matching upstream
  SHA256; executable archive member verified. Only arm64 runtime was exercised.
- `just --list`, rebuild dry-run, shell syntax and `git diff --check` passed.

## Limits

No full amd64 image build, no rebuild of the other seven template images, no
credentialed agent run, inbox/Daily launcher execution, mounted-extension test,
model/API/mail/Queue scan, schedule change or registry push. Existing active
image tags and containers were not replaced. Image smoke does not establish
end-to-end inbox or Daily correctness. No blocking incompatibility was observed
within the tested coverage; floating upstream releases can still change it.
