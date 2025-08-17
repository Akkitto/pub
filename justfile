# Strict, portable shell & env loading
set shell := ["bash", "-euo", "pipefail", "-c"]
set dotenv-load
set export

# Aliases
alias a   := all
alias i   := init
alias s   := serve
alias srv := serve
alias p   := publish
alias pub := publish
alias r   := deploy-raw
alias raw := deploy-raw

# Tooling & paths
root          := justfile_directory()
nu            := env_var_or_default("NU", "nu")
zola          := env_var_or_default("ZOLA", "zola")
script_hooks  := root / "utils" / "git_hook_install.nu"
script_deploy := root / "utils" / "deploy_raw.nu"
script_cname  := root / "utils" / "deploy_cname.nu"
config        := root / "config.toml"

# Exported env
export ZOLA_ENV := env_var_or_default("ZOLA_ENV", "production")

# Orchestrator: hooks first, then Zola
init: git-hooks zola-setup github-cname
  @echo "✓ Hooks installed, Zola initialised, Articles published (ZOLA_ENV=${ZOLA_ENV})."

# Publish complete with bells & whistles
publish: init deploy-raw

# Publish complete with bells & whistles
all: publish

# Publish complete with bells & whistles
default: all

# Helper: assert a binary exists
_check-bin cmd:
  @command -v "{{cmd}}" >/dev/null 2>&1 || { echo "Error: '{{cmd}}' not in PATH." >&2; exit 127; }

# Re-create CNAME for Github Pages
github-cname:
  @just _check-bin {{nu}}
  @"{{nu}}" "{{script_cname}}"

# Install Git hooks via Nushell script
git-hooks:
  @just _check-bin {{nu}}
  @"{{nu}}" "{{script_hooks}}"

# Initialize, then validate & build Zola site
zola-setup:
  @just _check-bin {{zola}}
  @if [ ! -f "{{config}}" ]; then \
      echo "No config.toml → running '{{zola}} init .'"; \
      "{{zola}}" init .; \
    fi
  @"{{zola}}" check
  @"{{zola}}" build

# Dev server (alias: `just s`)
serve:
  @just _check-bin {{zola}}
  @"{{zola}}" serve

# Finalise
deploy-raw:
  @just _check-bin {{nu}}
  @"{{nu}}" "{{script_deploy}}"