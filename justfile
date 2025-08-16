# Strict, portable shell & env loading
set shell := ["bash", "-euo", "pipefail", "-c"]
set dotenv-load
set export

# Aliases
alias i   := init
alias s   := serve
alias p   := publish
alias pub := publish

# Tooling & paths
root          := justfile_directory()
nu            := env_var_or_default("NU", "nu")
zola          := env_var_or_default("ZOLA", "zola")
script_hooks  := root / "utils" / "git_hook_install.nu"
script_deploy := root / "utils" / "deploy_raw.nu"
script_cname  := root / "utils" / "deploy_cname.nu"
config        := root / "config.toml"

# Exported env (override via .env or CLI)
export ZOLA_ENV := env_var_or_default("ZOLA_ENV", "production")

default: all

# Helper: assert a binary exists
_check-bin cmd:
  @command -v "{{cmd}}" >/dev/null 2>&1 || { echo "Error: '{{cmd}}' not in PATH." >&2; exit 127; }

github-cname:
  @just _check-bin {{nu}}
  @"{{nu}}" "{{script_cname}}"

# 1) Install Git hooks via Nushell script (single task, as requested)
git-hooks:
  @just _check-bin {{nu}}
  @"{{nu}}" "{{script_hooks}}"

# 2) Initialize (if needed), then validate & build Zola site
zola-setup:
  @just _check-bin {{zola}}
  @if [ ! -f "{{config}}" ]; then \
      echo "No config.toml → running '{{zola}} init .'"; \
      "{{zola}}" init .; \
    fi
  @"{{zola}}" check
  @"{{zola}}" build

# Orchestrator: hooks first, then Zola (left→right execution)
init: git-hooks zola-setup github-cname
  @echo "✓ Hooks installed, Zola initialised (ZOLA_ENV=${ZOLA_ENV})."

# Dev server (alias: `just s`)
serve:
  @just _check-bin {{zola}}
  @"{{zola}}" serve

publish:
  @just _check-bin {{nu}}
  @"{{nu}}" "{{script_deploy}}"

all: init publish