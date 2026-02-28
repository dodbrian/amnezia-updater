# AGENTS.md - Amnezia Updater

Guidance for agentic coding tools working in `/home/denis/source/amnezia`.

## Project Snapshot
- Purpose: update and maintain an existing Amnezia VPN (Xray-core) deployment.
- Primary code: `au.sh` (Bash CLI for config/build/update/backup/restore/version).
- Container build: `Dockerfile` (Alpine + Xray + startup script + sysctl tuning).
- This repo is not a full installer; it operates on an already-installed remote environment.
- Remote operations happen through SSH/SCP.

## Repository Files
- `au.sh` - operational CLI logic and safety checks.
- `Dockerfile` - image definition used by remote `build` flow.
- `README.md` - user docs and examples.
- `docs/` - notes/log artifacts.

## Cursor and Copilot Rules
- `.cursor/rules/` not found.
- `.cursorrules` not found.
- `.github/copilot-instructions.md` not found.
- No extra editor-agent policy files are currently active.

## Tooling Expectations
- Local required: `bash`, `ssh`, `scp`.
- Optional but recommended: `shellcheck`, `shfmt`, Docker CLI.
- Remote required: Docker engine, existing Amnezia container/network setup.
- Config file location: `${XDG_CONFIG_HOME:-$HOME/.config}/amnezia-updater/config`.

## Build Commands
- Local image build:
```bash
docker build -t amnezia-xray .
```
- Remote build with explicit Xray release:
```bash
./au.sh build v25.8.3
```
- Remote build with latest Xray release:
```bash
./au.sh build --latest
```

## Lint and Static Validation
- Bash syntax check (always available):
```bash
bash -n au.sh
```
- ShellCheck (if installed):
```bash
shellcheck au.sh
```
- Formatting diff (if `shfmt` installed):
```bash
shfmt -d -i 4 -ci -bn au.sh
```

## Test Strategy
- There is no formal unit/integration test suite in this repository.
- Validation is command-level and environment-level.
- Use static checks locally and runtime checks against the target VPS.

## Single-Test Guidance (Important)
- If asked to run a single test, prefer this focused check:
```bash
bash -n au.sh
```
- If SSH config is ready and remote checks are possible, use:
```bash
./au.sh version
```
- After modifying deploy/update flows, use:
```bash
./au.sh update --dry-run
```

## Manual Runtime Verification
- Confirm container exists and is running:
```bash
ssh amnezia "docker ps --format '{{.Names}}' | grep '^amnezia-xray$'"
```
- Check deployed Xray binary/version:
```bash
ssh amnezia "docker exec amnezia-xray xray version"
```
- Inspect port mappings:
```bash
ssh amnezia "docker port amnezia-xray"
```
- Watch recent logs:
```bash
ssh amnezia "docker logs --tail 100 -f amnezia-xray"
```

## Code Style Guidelines

### General Principles
- Keep edits minimal and scoped to the requested behavior.
- Preserve existing CLI UX text style unless asked to revise wording globally.
- Prefer extending existing helpers over introducing parallel logic paths.
- Avoid unnecessary dependencies and avoid broad refactors.

### Imports / Sourcing
- There are no imports/modules in current code.
- If adding sourced shell files, use explicit paths and existence checks.
- Keep sourcing predictable and near the top of the script.

### Formatting
- Follow existing 4-space indentation in `au.sh`.
- Keep one blank line between function blocks.
- Wrap long command pipelines for readability.
- Avoid trailing whitespace and noisy alignment changes.

### Types and Data Handling
- Treat CLI args, archive names, and SSH values as untrusted input.
- Validate numeric values (ports) with regex and range checks.
- Use Bash-safe tests: `[[ ... ]]` for expressions; quote expansions by default.
- Prefer explicit variable names over short abbreviations.

### Naming Conventions
- Global constants/config-like vars: uppercase (`DEFAULT_PORT`, `CONTAINER_NAME`).
- Local vars: lowercase snake_case (`remote_build_dir`, `archive_file`).
- Functions: lowercase snake_case verbs (`validate_port`, `check_container`).
- Keep command names consistent and imperative (`build`, `update`, `restore`).

### Error Handling
- Fail fast with clear messages: `echo "Error: ..."` and `exit 1`.
- Validate preconditions before mutating remote state.
- Never suppress SSH/Docker/tar failures unless intentionally handled.
- Preserve rollback/safety behavior in `update` flow.

### Bash-Specific Rules
- Keep shebang as `#!/bin/bash`.
- Keep `set -e` unless there is a strong reason to change behavior.
- Use `local` for function-scoped variables.
- Quote variables in commands (`"$var"`) unless splitting is explicitly desired.
- Prefer helper wrappers (`remote_ssh`, `run_remote_command`, SCP wrappers).
- Preserve `DRY_RUN` semantics for all mutating operations.

### Dockerfile Rules
- Keep base image and major tool versions explicit.
- Keep `ARG XRAY_RELEASE` flow intact with `v...` tag expectations.
- Maintain stable entrypoint contract: `dumb-init` + `/opt/amnezia/start.sh`.
- Be careful with sysctl/security changes; document rationale in commit/PR.

## Operational Safety for Agents
- Read `README.md`, `au.sh`, and `Dockerfile` before making code changes.
- After editing `au.sh`, run at least `bash -n au.sh`.
- If available, also run `shellcheck au.sh` and address high-signal findings.
- For remote-impacting changes, recommend `./au.sh update --dry-run` then `./au.sh version`.
- Do not commit backup archives, secrets, private keys, or host-specific credentials.

## Known Constraints
- No CI workflow is defined in this repo.
- No docker-compose file is present at repository root.
- End-to-end confidence depends on access to a real VPS environment.
