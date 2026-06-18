#!/usr/bin/env bash
# refresh-local-plugin.sh -- Maintainer helper for local plugin payload refresh.
#
# Default: rebuild and validate generated payloads, then refresh both the Claude
# Code and Codex installed-plugin caches so local dogfooding picks up changes.
# Opt out of either cache refresh with --no-codex or --no-claude-install.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PLUGIN_NAME="${SPECKIT_PLUGIN_NAME:-speckit-pro}"
MARKETPLACE="${SPECKIT_MARKETPLACE:-racecraft-plugins-public}"
CLAUDE_SCOPE="user"

RUN_BUILD=1
RUN_VALIDATE=1
RUN_CODEX=1
RUN_CLAUDE_INSTALL=1
RUN_CLAUDE_LAUNCH=0
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: scripts/refresh-local-plugin.sh [options]

Rebuild generated plugin payloads and refresh the local Claude Code and Codex
installed-plugin caches for maintainer dogfooding.

Default:
  Rebuild dist payloads, validate the Claude payload, refresh both the Claude
  Code and Codex installed-plugin caches, and print the recommended Claude Code
  local-development command:

    claude --plugin-dir dist/claude/speckit-pro

Options:
  --all                Refresh Codex and Claude installed-plugin caches (default).
  --codex              Refresh the Codex installed plugin via remove/add (default).
  --claude-install     Refresh Claude Code's installed plugin cache (default).
  --no-codex           Skip the Codex installed-plugin cache refresh.
  --no-claude-install  Skip Claude Code's installed-plugin cache refresh.
  --launch-claude      Launch Claude Code with --plugin-dir for this session.
  --scope SCOPE        Claude install scope: user, project, or local. Default: user.
  --no-build           Skip payload rebuild.
  --no-validate        Skip Claude payload validation.
  --dry-run            Print commands without running them.
  -h, --help           Show this help.

Environment:
  SPECKIT_PLUGIN_NAME   Plugin name. Default: speckit-pro
  SPECKIT_MARKETPLACE   Marketplace name. Default: racecraft-plugins-public
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

usage_error() {
  echo "error: $*" >&2
  echo >&2
  usage >&2
  exit 2
}

quote_args() {
  local arg
  for arg in "$@"; do
    printf ' %q' "$arg"
  done
}

run_cmd() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '+'
    quote_args "$@"
    printf '\n'
  else
    "$@"
  fi
}

run_in_repo() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '+ cd %q &&' "$REPO_ROOT"
    quote_args "$@"
    printf '\n'
  else
    (cd "$REPO_ROOT" && "$@")
  fi
}

require_cmd() {
  if [ "$DRY_RUN" -eq 1 ]; then
    return
  fi

  if ! command -v "$1" >/dev/null 2>&1; then
    die "required command not found: $1"
  fi
}

plugin_selector() {
  printf '%s@%s' "$PLUGIN_NAME" "$MARKETPLACE"
}

claude_payload_dir() {
  printf '%s/dist/claude/%s' "$REPO_ROOT" "$PLUGIN_NAME"
}

codex_payload_dir() {
  printf '%s/dist/codex/%s' "$REPO_ROOT" "$PLUGIN_NAME"
}

claude_dev_command() {
  printf 'claude --plugin-dir %q\n' "$(claude_payload_dir)"
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --all)
        RUN_CODEX=1
        RUN_CLAUDE_INSTALL=1
        ;;
      --codex)
        RUN_CODEX=1
        ;;
      --claude-install)
        RUN_CLAUDE_INSTALL=1
        ;;
      --no-codex)
        RUN_CODEX=0
        ;;
      --no-claude-install)
        RUN_CLAUDE_INSTALL=0
        ;;
      --launch-claude)
        RUN_CLAUDE_LAUNCH=1
        ;;
      --scope)
        [ "$#" -ge 2 ] || usage_error "--scope requires a value"
        CLAUDE_SCOPE="$2"
        shift
        ;;
      --scope=*)
        CLAUDE_SCOPE="${1#--scope=}"
        ;;
      --no-build)
        RUN_BUILD=0
        ;;
      --no-validate)
        RUN_VALIDATE=0
        ;;
      --dry-run)
        DRY_RUN=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        usage_error "unknown option: $1"
        ;;
    esac
    shift
  done

  case "$CLAUDE_SCOPE" in
    user|project|local) ;;
    *) usage_error "--scope must be one of: user, project, local" ;;
  esac
}

validate_layout() {
  [ -x "$REPO_ROOT/scripts/build-plugin-payloads.sh" ] || \
    die "build script not executable: $REPO_ROOT/scripts/build-plugin-payloads.sh"

  if [ "$RUN_BUILD" -eq 0 ] || [ "$DRY_RUN" -eq 1 ]; then
    [ -d "$(claude_payload_dir)" ] || die "Claude payload not found: $(claude_payload_dir)"
    [ -d "$(codex_payload_dir)" ] || die "Codex payload not found: $(codex_payload_dir)"
  fi
}

build_payloads() {
  echo "==> Building generated Claude and Codex payloads ..."
  run_in_repo ./scripts/build-plugin-payloads.sh
}

validate_claude_payload() {
  require_cmd claude
  echo "==> Validating Claude Code payload ..."
  run_cmd claude plugin validate "$(claude_payload_dir)"
}

claude_marketplace_root() {
  claude plugin marketplace list 2>/dev/null | awk -v name="$MARKETPLACE" '
    index($0, name) { found=1; next }
    found && /Source: Directory/ {
      sub(/^.*Source: Directory \(/, "")
      sub(/\).*$/, "")
      print
      exit
    }
    found && /Source:/ { exit }
  '
}

ensure_claude_marketplace_is_local() {
  local root

  if [ "$DRY_RUN" -eq 1 ]; then
    printf '+ claude plugin marketplace list # verify %s points at %q\n' "$MARKETPLACE" "$REPO_ROOT"
    return
  fi

  root="$(claude_marketplace_root || true)"

  if [ "$root" = "$REPO_ROOT" ]; then
    return
  fi

  if [ -n "$root" ]; then
    die "Claude marketplace '$MARKETPLACE' points at '$root', expected '$REPO_ROOT'. Remove or update it explicitly before refreshing."
  fi

  echo "==> Adding Claude marketplace $MARKETPLACE from $REPO_ROOT ..."
  run_cmd claude plugin marketplace add "$REPO_ROOT" --scope "$CLAUDE_SCOPE"
}

refresh_claude_install() {
  require_cmd claude
  ensure_claude_marketplace_is_local

  echo "==> Refreshing $(plugin_selector) in Claude Code ($CLAUDE_SCOPE scope) ..."
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '+ claude plugin uninstall %q --scope %q -y || true\n' "$(plugin_selector)" "$CLAUDE_SCOPE"
  else
    claude plugin uninstall "$(plugin_selector)" --scope "$CLAUDE_SCOPE" -y >/dev/null 2>&1 || true
  fi
  run_cmd claude plugin install "$(plugin_selector)" --scope "$CLAUDE_SCOPE"
  echo "    Restart Claude Code or run /reload-plugins in an existing session."
}

codex_marketplace_root() {
  codex plugin marketplace list 2>/dev/null | awk -v name="$MARKETPLACE" '$1 == name {print $2; exit}'
}

ensure_codex_marketplace_is_local() {
  local root

  if [ "$DRY_RUN" -eq 1 ]; then
    printf '+ codex plugin marketplace list # verify %s points at %q\n' "$MARKETPLACE" "$REPO_ROOT"
    return
  fi

  root="$(codex_marketplace_root || true)"

  if [ "$root" = "$REPO_ROOT" ]; then
    return
  fi

  if [ -n "$root" ]; then
    die "Codex marketplace '$MARKETPLACE' points at '$root', expected '$REPO_ROOT'. Remove or update it explicitly before refreshing."
  fi

  echo "==> Adding Codex marketplace $MARKETPLACE from $REPO_ROOT ..."
  run_cmd codex plugin marketplace add "$REPO_ROOT"
}

refresh_codex_install() {
  require_cmd codex
  ensure_codex_marketplace_is_local

  echo "==> Refreshing $(plugin_selector) in Codex ..."
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '+ codex plugin remove %q || true\n' "$(plugin_selector)"
  else
    codex plugin remove "$(plugin_selector)" >/dev/null 2>&1 || true
  fi
  run_cmd codex plugin add "$(plugin_selector)"
  echo "    Start a new Codex thread to pick up refreshed plugin skills and tools."
}

launch_claude_with_local_payload() {
  require_cmd claude
  echo "==> Launching Claude Code with local payload override ..."
  run_cmd claude --plugin-dir "$(claude_payload_dir)"
}

print_guidance() {
  if [ "$RUN_CLAUDE_LAUNCH" -eq 0 ]; then
    echo
    echo "Claude Code local-development command:"
    printf '  %s\n' "$(claude_dev_command)"
  fi

  if [ "$RUN_CLAUDE_INSTALL" -eq 0 ]; then
    echo "Skipped Claude installed-cache refresh (--no-claude-install)."
  fi

  if [ "$RUN_CODEX" -eq 0 ]; then
    echo "Skipped Codex installed-cache refresh (--no-codex)."
  fi
}

main() {
  parse_args "$@"
  validate_layout

  if [ "$RUN_BUILD" -eq 1 ]; then
    build_payloads
  fi

  if [ "$RUN_VALIDATE" -eq 1 ]; then
    validate_claude_payload
  fi

  if [ "$RUN_CODEX" -eq 1 ]; then
    refresh_codex_install
  fi

  if [ "$RUN_CLAUDE_INSTALL" -eq 1 ]; then
    refresh_claude_install
  fi

  if [ "$RUN_CLAUDE_LAUNCH" -eq 1 ]; then
    launch_claude_with_local_payload
  fi

  print_guidance
}

main "$@"
