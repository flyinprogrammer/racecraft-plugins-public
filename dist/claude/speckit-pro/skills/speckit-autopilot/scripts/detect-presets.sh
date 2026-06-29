#!/usr/bin/env bash
# detect-presets.sh — Detect installed presets and extensions
#
# Usage: detect-presets.sh
# Output: JSON with preset info, extensions, template resolution
# Exit:   0 = success (even if no presets found)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/specify-cli.sh"

extract_preset_version() {
  local preset_file="$1"
  awk '
    /^[[:space:]]*version:[[:space:]]*/ {
      sub(/^[[:space:]]*version:[[:space:]]*/, "")
      sub(/[[:space:]]+#.*$/, "")
      gsub(/^[[:space:]]+|[[:space:]]+$/, "")
      quote = substr($0, 1, 1)
      if (length($0) >= 2 && (quote == "\"" || quote == sprintf("%c", 39)) && substr($0, length($0), 1) == quote) {
        $0 = substr($0, 2, length($0) - 2)
      }
      print
      exit
    }
  ' "$preset_file" 2>/dev/null
}

# Detect presets — build a jq-safe JSON array
presets_json="[]"
if ls .specify/presets/*/preset.yml >/dev/null 2>&1; then
  preset_items=()
  for preset_file in .specify/presets/*/preset.yml; do
    preset_dir=$(dirname "$preset_file")
    preset_name=$(basename "$preset_dir")
    # Extract key fields from YAML (basic parsing without yq).
    # The preset.yml schema nests `version:` under `preset:`, so it arrives
    # indented (e.g. `  version: "1.0.0"`). Allow leading whitespace so both the
    # nested schema and a flat top-level `version:` match, and require the literal
    # `version:` immediately after the optional indent so `schema_version:` is
    # excluded. Mirrors installed_version() in install-curated-set.sh.
    version=$(extract_preset_version "$preset_file" || echo "")
    version="${version:-unknown}"
    templates=$(grep -A1 'replaces:' "$preset_file" 2>/dev/null | grep -v 'replaces:' | sed 's/.*"\([^"]*\)".*/\1/' | tr '\n' ',' | sed 's/,$//' || echo "")
    # Use jq to safely build each preset object (escapes all string values)
    item=$(jq -cn \
      --arg name "$preset_name" \
      --arg version "$version" \
      --arg templates "$templates" \
      '{"name":$name,"version":$version,"templates":$templates}')
    preset_items+=("$item")
  done
  presets_json=$(printf '%s\n' "${preset_items[@]}" | jq -s '.')
fi

# Detect extensions from .registry (most authoritative)
extensions_json='"see .specify/extensions/.registry"'
if [ ! -f ".specify/extensions/.registry" ]; then
  if ls .specify/extensions/*/extension.yml >/dev/null 2>&1; then
    ext_names=()
    for ext_file in .specify/extensions/*/extension.yml; do
      ext_names+=("$(basename "$(dirname "$ext_file")")")
    done
    extensions_json=$(printf '%s\n' "${ext_names[@]}" | jq -R . | jq -s '.')
  else
    extensions_json='[]'
  fi
fi

# Check hooks configuration
hooks="none"
if [ -f ".specify/extensions.yml" ]; then
  hook_count=$(grep -c 'before_\|after_' .specify/extensions.yml 2>/dev/null || echo "0")
  if [ "$hook_count" -gt 0 ]; then
    hooks="$hook_count hook events configured"
  fi
fi

# Template resolution (if specify CLI available)
tasks_template="default"
spec_template="default"
plan_template="default"
if speckit_have_specify; then
  tasks_template=$(speckit_specify preset resolve tasks-template 2>/dev/null || echo "default")
  spec_template=$(speckit_specify preset resolve spec-template 2>/dev/null || echo "default")
  plan_template=$(speckit_specify preset resolve plan-template 2>/dev/null || echo "default")
fi

has_presets="false"
if [ "$presets_json" != "[]" ]; then
  has_presets="true"
fi

# Assemble final JSON safely via jq
jq -cn \
  --argjson has_presets "$has_presets" \
  --argjson presets "$presets_json" \
  --argjson extensions "$extensions_json" \
  --arg hooks "$hooks" \
  --arg tasks_template "$tasks_template" \
  --arg spec_template "$spec_template" \
  --arg plan_template "$plan_template" \
  '{
    "has_presets": $has_presets,
    "presets": $presets,
    "extensions": $extensions,
    "hooks": $hooks,
    "templates": {
      "tasks": $tasks_template,
      "spec": $spec_template,
      "plan": $plan_template
    }
  }'
