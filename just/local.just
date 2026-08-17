# just/local.just — the `local` namespace: boot an orchestrator agent that works
# on THIS machine.
#
# `just local cc` drives the factory (the ADWs in `just adw`) right here.
# `just sbx  ...` drives sandboxes, where the factory runs on a throwaway VM.
# The namespace is the answer to "where does the work happen".
#
# Meant to run inside a sandbox: there this is exactly how you boot an
# orchestrator onto that sandbox's own factory.
#
# A MODULE inherits NOTHING from the root justfile, so the settings below are
# repeated deliberately. `shell` matters most: `ipi` is a zsh FUNCTION, not a
# binary, so it only resolves through an interactive zsh. Drop this line and
# `just local ipi` fails with "command not found" while cc and pi keep working.
set shell := ["zsh", "-ic"]
set working-directory := '..'
set positional-arguments

export SHELL_SESSIONS_DISABLE := "1"

# list the local commands
default:
    @just --list local

# Install the repository's public model roster without copying either host key.
# Existing content is never overwritten; it must pass the same validation.
setup:
    #!/usr/bin/env bash
    set -euo pipefail
    template="sandbox_mount/guest/models.json.tmpl"
    target="${PI_MODELS_PATH:-$HOME/.pi/agent/models.json}"
    [[ -f "$template" ]] || { echo "local setup: missing $template" >&2; exit 1; }
    [[ ! -L "$target" ]] || { echo "local setup: refusing symlink $target" >&2; exit 1; }
    [[ ! -e "$target" || -f "$target" ]] || { echo "local setup: registry is not a regular file: $target" >&2; exit 1; }
    if [[ ! -e "$target" ]]; then
      umask 077
      mkdir -p "$(dirname "$target")"
      cp "$template" "$target"
      echo "local setup: installed $target"
    else
      echo "local setup: preserving existing $target"
    fi
    chmod 600 "$target"
    just local check-models

# Read-only preflight for the registry used by local Pi/ADW calls.
check-models:
    #!/usr/bin/env bash
    set -euo pipefail
    target="${PI_MODELS_PATH:-$HOME/.pi/agent/models.json}"
    [[ ! -L "$target" && -f "$target" ]] || { echo "local models: missing regular registry $target; run: just local setup" >&2; exit 1; }
    python3 - "$target" <<'PY'
    import json
    import stat
    import sys
    from pathlib import Path

    path = Path(sys.argv[1])
    try:
        registry = json.loads(path.read_text(encoding="utf-8"))
        provider = registry["providers"]["openrouter"]
        models = provider["models"]
    except (OSError, UnicodeError, json.JSONDecodeError, KeyError, TypeError) as exc:
        raise SystemExit(f"local models: invalid registry {path}: {exc}") from exc
    if provider.get("apiKey") != "env:OPENROUTER_API_KEY":
        raise SystemExit("local models: apiKey must be env:OPENROUTER_API_KEY (never the provisioning key)")
    required_cost = {"input", "output", "cacheRead", "cacheWrite"}
    if not models or any(set(model.get("cost", {})) != required_cost for model in models):
        raise SystemExit("local models: every model needs the complete four-field cost table")
    mode = stat.S_IMODE(path.stat().st_mode)
    if mode != 0o600:
        raise SystemExit(f"local models: {path} mode is {mode:o}, expected 600")
    print(f"local models: OK ({len(models)} models, mode 600, inference-key placeholder)")
    PY

# Claude Code orchestrator — reads the sssf overview, then handles your ask
cc: setup
    claude --dangerously-skip-permissions "Read and Execute .claude/skills/sssf/SKILL.md"

# Pi orchestrator — same posture, pi harness
pi: setup
    pi "Read and Execute .claude/skills/sssf/SKILL.md"

# ipi orchestrator — same posture, ipi harness
ipi: setup
    ipi "Read and Execute .claude/skills/sssf/SKILL.md" --no-skills
