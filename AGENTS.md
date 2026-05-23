# sannux Agent Guide

AI context for this repository. Read this before changing files.

---

## Communication / Language

- **Tone:** direct, practical, no corporate fluff.
- **Chat language:** match the user's language.
- **Project language:** English for code, git, GitHub, docs, issues, PRs, and
  `README.md` (except `README-PT-BR.md` files, always keep Portuguese docs up to
  date).

---

## Project Context

`sannux` means **Sandbox Linux**.

This repository holds Docker templates for running AI coding agents in isolated
containers. Each template should be self-contained enough to copy out of the
repo and run on its own.

Users may copy one of these templates to a VPS and run an autonomous or
semi-autonomous agent there.
Assume many users will keep the default shape of the template and only edit the
minimum required variables.

Main goals:

- Keep agent credentials and state isolated from the host machine.
- Mount only the intended workspace into the container.
- Run agents as non-root users by default.
- Provide practical templates, not a production platform.
- Support separate agents with separate workspaces, agent homes, tools, and
  provider keys.

This is a security-sensitive sandbox/tooling repo, but it is also experimental.
Prefer simple, inspectable Docker and shell code over clever abstractions.

---

## Workflow

All repository work must use the full collaboration workflow, even for small
documentation tweaks:

- issue -> branch -> small conventional commits -> PR -> squash merge -> delete
  the branch.
- Check open issues before starting work. Reuse an existing issue when it
  matches the request; otherwise create or propose one.
- Keep branches focused on one issue and one task.
- Finish accepted work by squash-merging the PR and deleting the branch.
- One focused task per session is the default.

Commit style:

```text
type(scope): short imperative description

Optional body explaining what changed and why.
```

Use conventional commit types such as `feat`, `fix`, `docs`, `chore`,
`refactor`, `test`, and `ci`.

---

## Agent Operating Rules

These are hard rules:

- Read the relevant files before changing anything.
- Make the smallest safe change that solves the request.
- Do not silently rewrite architecture, rename public paths, or move files.
- Do not add dependencies, services, frameworks, build tools, queues, caches, or
  ORMs without a clear reason.
- Do not delete comments, tests, docs, or examples unless they are wrong or the
  user asked for it.
- Do not claim something works without running the relevant check, or clearly
  saying why it was not run.
- Do not commit `.env`, secrets, tokens, private keys, credentials, local agent
  state, logs, caches, or generated throwaway output.
- No destructive git operations without explicit user confirmation.

If a request conflicts with these rules, stop and explain the tradeoff plainly.

---

## Engineering Defaults

Treat these as strong preferences, not bureaucracy.

- Prefer boring, explicit, maintainable code.
- Follow the existing conventions of the language, framework, and local files.
- Prefer editing existing code over creating parallel implementations.
- Prefer clear domain names over vague names like `data`, `handler`, `manager`,
  `processor`, `service`, `utils`, `helper`, `thing`, or `item`.
- Avoid duplication of business rules, validation rules, and non-trivial
  transformations.
- Prefer early returns and shallow nesting.
- Keep functions and files focused, but do not split simple linear code just to
  satisfy a line count.
- Add abstractions only when they remove real complexity or match an existing
  project pattern.
- Preserve public behavior unless the task explicitly asks for a change.

For this repo specifically:

- Template folders under `templates/<template>/` should remain self-contained.
- Root-level helpers such as `justfile` are convenience only; templates should
  still work with plain `docker compose`.
- `docs/template-contract.md` is the canonical template contract. Read it before
  changing templates, and run `just check` before finishing template or contract
  documentation changes.
- Templates must require explicit `WORKSPACE_PATH` and `AGENT_HOME_PATH` values.
  Do not default these paths to folders inside this repository.
- Keep the happy path safe for users who barely read the docs. The template
  should fail fast when required host paths are missing instead of silently
  creating repo-local workspaces or agent homes.
- Dockerfiles and compose files should stay readable and easy to audit.
- Security hardening should be practical and documented. Avoid "paranoid" setup
  that makes the template hard to run unless the task asks for it.
- When adding generated files, caches, agent homes, or logs, check `.gitignore`.

---

## Types, Inputs, and Errors

- Use explicit types at public boundaries when the language supports it.
- Avoid `any` or loose dictionaries when the expected shape is known.
- Validate external input at the boundary: CLI args, env vars, paths, URLs,
  compose variables, API responses, and user-controlled data.
- Error messages should include useful context: what failed, the offending value
  when safe, and what was expected.
- Preserve original errors when wrapping exceptions.

---

## Tests and Verification

Prefer one obvious project command when available.

Common checks for this repo:

```sh
just check
just --list
just templates
docker compose config
docker compose build
docker compose run --rm agent
```

Pick the smallest useful verification for the change:

- Docs-only change: inspect links/commands/examples and check formatting by
  reading the rendered Markdown when practical.
- Docker/compose change: run `docker compose config` in the affected template.
- Script/justfile change: run the affected recipe or a dry-run equivalent.
- Behavior change: add or update a focused test/check when practical.

Do not call real external APIs in automated tests unless the test is explicitly
an integration check.

---

## Documentation

Update docs when the user-facing behavior changes.

When changing any template, treat documentation as part of the change. In the
same pass, update or explicitly verify:

- Root docs: `README.md` and `README-PT-BR.md`.
- Changed template docs: `templates/<template>/README.md` and
  `templates/<template>/README-PT-BR.md`.

Good places:

- Root `README.md`: project purpose, threat model, repo layout, normal usage.
- `docs/template-contract.md`: cross-template contract, validation, and
  exception rules.
- `templates/<template>/README.md`: template-specific setup and commands.
- `docs/`: design notes and rationale.

Keep docs practical. Prefer commands that the user can run over broad prose.

---

## Communication

- If the request is ambiguous, ask a brief clarifying question before writing
  code.
- Explain blockers and tradeoffs plainly.
- In the final response, say what changed and what was verified.
- If something should be done later, leave a concrete handoff instead of vague
  advice.

---

## Security / Safety

Always assume local files, shell arguments, URLs, environment variables, and
mounted paths can be dangerous.

- Never hardcode or log secrets.
- Never commit real `.env` files.
- Keep `.env.example` safe and fake.
- Avoid shell string concatenation with unsanitized input.
- Prefer least-privilege container settings.
- Do not mount host home directories, SSH keys, cloud credentials, package
  manager tokens, or global GitHub config into agent containers.
- Keep agent workspaces and persisted homes outside the `sannux` checkout.
- If a template needs a credential, pass only the narrow credential it needs and
  document the blast radius.
