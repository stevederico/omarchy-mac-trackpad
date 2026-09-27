#!/usr/bin/env bash
# Remove what install.sh added. See README.md.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"

FORCE=0

usage() {
  cat <<EOF
Usage: ./uninstall.sh [options]

Removes the files and blocks install.sh added. Anything else in the
same files is left alone. Shows every change first and asks.

  -n, --dry-run      Show what would change. Touch nothing.
  -y, --yes          Apply without asking.
      --hypr-only    Only the Hyprland part (~/.config/hypr). No sudo.
      --system-only  Only the /etc part (libinput quirks, udev).
      --force        Also remove udev files of the same name that this
                     tool did not install.
  -h, --help         Show this help.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n | --dry-run) DRY_RUN=1 ;;
      -y | --yes) ASSUME_YES=1 ;;
      --hypr-only) DO_SYSTEM=0 ;;
      --system-only) DO_HYPR=0 ;;
      --force) FORCE=1 ;;
      -h | --help)
        usage
        exit 0
        ;;
      *) die "unknown option: $1 (try --help)" ;;
    esac
    shift
  done
  if [[ $DO_HYPR -eq 0 && $DO_SYSTEM -eq 0 ]]; then
    die "--hypr-only and --system-only together leave nothing to do"
  fi
}

# Drop our block from a file. Remove the file when nothing else is left.
remove_block() {
  local dst=$1 owner=$2 staged=$3
  if ! has_block "$dst"; then
    if [[ $MODE == plan ]]; then
      say "  no block   $dst"
    fi
    return 0
  fi
  strip_block "$dst" >"$staged"
  if has_content "$staged"; then
    write_file "$staged" "$dst" "$owner"
  else
    remove_file "$dst" "$owner"
  fi
}

# Remove a udev file only when install.sh put it there.
remove_owned() {
  local dst=$1
  if [[ -f $dst && $FORCE -ne 1 ]] && ! grep -qF "$OWNED_TAG" "$dst"; then
    if [[ $MODE == plan ]]; then
      say "  kept       $dst (not installed by this tool, --force removes it)"
    fi
    return 0
  fi
  remove_file "$dst" root
}

do_hypr() {
  say "Hyprland (~/.config/hypr):"
  # Drop the require lines first so Hyprland never loads a missing module.
  remove_block "$HYPR_MAIN" user "$STAGE/hyprland.lua"
  remove_file "$HYPR_SNIPPET" user
  remove_file "$HYPR_OPTIONAL" user
}

do_system() {
  say "System (/etc, needs sudo):"
  remove_block "$QUIRKS_DST" root "$STAGE/local-overrides.quirks"
  remove_owned "$HWDB_DST"
  remove_owned "$RULES_DST"
}

run_steps() {
  if [[ $DO_HYPR -eq 1 ]]; then
    do_hypr
  fi
  if [[ $DO_SYSTEM -eq 1 ]]; then
    do_system
  fi
}

main() {
  parse_args "$@"
  init

  MODE=plan
  run_steps
  say ""
  if [[ $CHANGED -eq 0 ]]; then
    say "Nothing installed. Nothing to do."
    exit 0
  fi
  if [[ $DRY_RUN -eq 1 ]]; then
    say "Dry run. Nothing was changed."
    exit 0
  fi
  sudo_notice
  confirm || die "aborted. Nothing was changed."
  say ""

  MODE=apply
  CHANGED=0
  SYSTEM_CHANGED=0
  run_steps
  if [[ $SYSTEM_CHANGED -eq 1 ]]; then
    reload_udev
  fi
  say ""
  backup_notice
  say "Done."
  if [[ $DO_SYSTEM -eq 1 ]]; then
    say "Reboot to drop the /etc part from the running session."
  fi
}

main "$@"
