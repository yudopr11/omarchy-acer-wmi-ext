#!/usr/bin/env bash
set -euo pipefail

if (( EUID == 0 )); then
  printf 'Run this as your normal user; the script invokes sudo for installation.\n' >&2
  exit 1
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
helper_source="$script_dir/acer-wmi-ext-omarchy-control"
policy_source="$repo_dir/polkit/org.acer-wmi-ext.omarchy.policy"

[[ -x "$helper_source" ]] || {
  printf 'Control helper is missing or not executable: %s\n' "$helper_source" >&2
  exit 1
}
[[ -f "$policy_source" ]] || {
  printf 'Polkit policy is missing: %s\n' "$policy_source" >&2
  exit 1
}

sudo install -Dm755 "$helper_source" /usr/local/bin/acer-wmi-ext-omarchy
sudo install -Dm644 "$policy_source" /usr/share/polkit-1/actions/org.acer-wmi-ext.omarchy.policy

printf 'Installed the Acer WMI Omarchy control helper and polkit policy.\n'
printf 'The plugin will request administrator authentication when it changes battery or USB settings.\n'
