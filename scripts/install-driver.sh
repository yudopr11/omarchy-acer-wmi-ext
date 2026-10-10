#!/usr/bin/env bash
set -euo pipefail

readonly UPSTREAM_URL="https://github.com/TenSeventy7/acer-wmi-ext.git"
readonly UPSTREAM_COMMIT="78aaf9392e1fbdd62c3ec9944e9615505485ec04"
readonly SYSFS_DIR="/sys/bus/wmi/drivers/acer-wmi-ext"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/install-driver.sh

Fetches the pinned acer-wmi-ext source, builds it for the running kernel,
then asks sudo to load it for this boot only. Does not install or autoload it.
Run from an interactive terminal as a normal user.
EOF
}

fail() {
  printf 'acer-wmi-ext driver setup: %s\n' "$1" >&2
  exit 1
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  "")
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

if (( EUID == 0 )); then
  fail 'run as your normal user; sudo is used only to load the module.'
fi

for command in git make sudo; do
  command -v "$command" >/dev/null 2>&1 || fail "required command not found: $command"
done

kernel_release="$(uname -r)"
headers_dir="/lib/modules/$kernel_release/build"
[[ -d "$headers_dir" ]] || fail "matching kernel headers are missing: $headers_dir"
[[ ! -d "$SYSFS_DIR" ]] || {
  printf 'acer-wmi-ext is already loaded.\n'
  exit 0
}
[[ -t 0 ]] || fail 'run this from an interactive terminal so you can confirm the kernel module load.'

cat <<EOF
This will fetch upstream acer-wmi-ext at commit $UPSTREAM_COMMIT,
build it for kernel $kernel_release, and load it into the running kernel.
It will not install the module or configure it to load after reboot.
The upstream driver is experimental; fan and USB support is documented for
Acer Swift Go 14 SFG14-73 only.
EOF
read -r -p 'Continue? [y/N] ' answer
case "${answer,,}" in
  y|yes)
    ;;
  *)
    printf 'Cancelled; no system changes were made.\n'
    exit 0
    ;;
esac

build_root="$(mktemp -d "${TMPDIR:-/tmp}/acer-wmi-ext-build.XXXXXXXX")"
trap 'rm -rf -- "$build_root"' EXIT
source_dir="$build_root/source"

printf '\nFetching upstream source...\n'
if ! git clone --quiet "$UPSTREAM_URL" "$source_dir"; then
  fail 'could not clone the upstream repository.'
fi
if ! git -C "$source_dir" checkout --quiet --detach "$UPSTREAM_COMMIT"; then
  fail "pinned upstream commit is unavailable: $UPSTREAM_COMMIT"
fi
actual_commit="$(git -C "$source_dir" rev-parse HEAD)"
[[ "$actual_commit" == "$UPSTREAM_COMMIT" ]] || fail 'upstream source did not match the pinned commit.'

printf '\nBuilding acer-wmi-ext for %s...\n' "$kernel_release"
if ! make -C "$source_dir"; then
  fail 'build failed; no module was loaded.'
fi
module_path="$source_dir/acer-wmi-ext.ko"
[[ -s "$module_path" ]] || fail 'build completed without producing acer-wmi-ext.ko.'

printf '\nLoading the kernel module...\n'
if ! sudo insmod "$module_path"; then
  fail 'module load failed. Check Secure Boot policy and kernel logs; the module was not installed persistently.'
fi

if [[ ! -d "$SYSFS_DIR" ]]; then
  fail "module was inserted, but $SYSFS_DIR is missing; check kernel logs and hardware support."
fi

printf '\nacer-wmi-ext loaded for this boot. Reopen the Omarchy widget to refresh its status.\n'
printf 'The temporary build files will be removed; the loaded module remains active until reboot.\n'
