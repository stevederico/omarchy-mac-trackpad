#!/usr/bin/env bash
# Install the Mac trackpad config for Omarchy. See README.md.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"

TESTED_MODEL="MacBookPro16,1"
TESTED_USB_ID="0340"

WITH_OPTIONAL=0
FORCE=0
MODEL=""
USB_ID=""
TESTED=0

usage() {
  cat <<EOF
Usage: ./install.sh [options]

Installs Mac-style trackpad settings for Omarchy on Intel T2 MacBooks.
Shows every change first and asks before applying. Safe to re-run.

  -n, --dry-run        Show what would change. Touch nothing.
  -y, --yes            Apply without asking.
      --with-optional  Also install the laptop-tuned pointer curve and
                       scroll_factor (tuned on $TESTED_MODEL).
      --hypr-only      Only the Hyprland part (~/.config/hypr). No sudo.
      --system-only    Only the /etc part (libinput quirks, udev).
      --model NAME     Mac model, e.g. MacBookPro16,1. Default: from DMI.
      --usb-id XXXX    Trackpad USB product id, e.g. 0340. Default: detected.
      --force          Install the /etc part on a model other than $TESTED_MODEL.
  -h, --help           Show this help.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n | --dry-run) DRY_RUN=1 ;;
      -y | --yes) ASSUME_YES=1 ;;
      --with-optional) WITH_OPTIONAL=1 ;;
      --hypr-only) DO_SYSTEM=0 ;;
      --system-only) DO_HYPR=0 ;;
      --force) FORCE=1 ;;
      --model)
        [[ $# -ge 2 ]] || die "--model needs a value"
        MODEL=$2
        shift
        ;;
      --usb-id)
        [[ $# -ge 2 ]] || die "--usb-id needs a value"
        USB_ID=$2
        shift
        ;;
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

detect_model() {
  if [[ -r /sys/class/dmi/id/product_name ]]; then
    cat /sys/class/dmi/id/product_name
  fi
}

# USB product id of the internal trackpad, read from the live device.
detect_usb_id() {
  [[ -r /proc/bus/input/devices ]] || return 0
  awk '
    /^I:/ {
      id = ""
      if (match($0, /Vendor=05ac Product=[0-9a-fA-F]+/)) {
        id = substr($0, RSTART + 20, RLENGTH - 20)
      }
    }
    /^N: Name=".*Apple Internal Keyboard \/ Trackpad/ {
      if (id != "") { print id; exit }
    }
  ' /proc/bus/input/devices
}

# T2 trackpad USB product ids from the kernel (hid-ids.h, WELLSPRINGT2_*).
known_usb_id() {
  case "$1" in
    MacBookAir8,1) echo 027a ;;
    MacBookPro15,2) echo 027b ;;
    MacBookPro15,1) echo 027c ;;
    MacBookPro15,4) echo 027d ;;
    MacBookPro16,2) echo 027e ;;
    MacBookPro16,3) echo 027f ;;
    MacBookAir9,1) echo 0280 ;;
    MacBookPro16,1) echo 0340 ;;
    *) return 1 ;;
  esac
}

resolve_target() {
  if [[ -z $MODEL ]]; then
    MODEL=$(detect_model)
  fi
  [[ $MODEL =~ ^[A-Za-z0-9,\ ._-]+$ ]] || die "could not read the machine model. Pass --model."
  if [[ -z $USB_ID ]]; then
    USB_ID=$(detect_usb_id)
  fi
  if [[ -z $USB_ID ]]; then
    USB_ID=$(known_usb_id "$MODEL" || true)
  fi
  USB_ID=${USB_ID,,}
  USB_ID=${USB_ID#0x}

  if [[ $MODEL == "$TESTED_MODEL" && $USB_ID == "$TESTED_USB_ID" ]]; then
    TESTED=1
    return 0
  fi
  if [[ $MODEL != MacBook* ]]; then
    die "this machine is '$MODEL', not a MacBook. The /etc files only match Apple T2 trackpads. Use --hypr-only for the Hyprland part."
  fi
  [[ $USB_ID =~ ^[0-9a-f]{4}$ ]] || die "could not find the trackpad USB product id for $MODEL. Pass --usb-id (see README)."
  if [[ $FORCE -ne 1 ]]; then
    die "$MODEL (trackpad 05ac:$USB_ID) is untested. The values were tuned on $TESTED_MODEL. Re-run with --force to install them matched to this model, or --hypr-only to skip /etc."
  fi
  warn "$MODEL (trackpad 05ac:$USB_ID) is untested. Thresholds were tuned on $TESTED_MODEL."
}

# Copy a shipped /etc file, retargeted when the model is not the tested one.
render() {
  local src=$1 dst=$2
  if [[ $TESTED -eq 1 ]]; then
    cp "$src" "$dst"
    return 0
  fi
  # AttrSizeHint is the physical size of the 16-inch pad. Drop it elsewhere
  # so libinput keeps its own value.
  sed -e "s/$TESTED_MODEL/$MODEL/g" \
    -e "s/$TESTED_USB_ID/$USB_ID/g" \
    -e '/^AttrSizeHint=/d' \
    "$src" >"$dst"
}

stage_hypr_main() {
  {
    strip_block "$HYPR_MAIN"
    say "-- $MARK_BEGIN"
    say "-- Managed by $NAME. Remove with its uninstall.sh."
    say 'require("hypr.mac-trackpad")'
    if [[ $WITH_OPTIONAL -eq 1 ]]; then
      say 'require("hypr.mac-trackpad-optional")'
    fi
    say "-- $MARK_END"
  } >"$STAGE/hyprland.lua"
}

stage_quirks() {
  render "$HERE/etc/libinput/local-overrides.quirks" "$STAGE/quirks.section"
  strip_block "$QUIRKS_DST" >"$STAGE/quirks.rest"
  if [[ $MODE == plan ]] && grep -qF "Apple Internal Keyboard / Trackpad" "$STAGE/quirks.rest"; then
    warn "$QUIRKS_DST already has its own section for this trackpad. Ours is added after it and wins where both set a value."
  fi
  {
    cat "$STAGE/quirks.rest"
    say "# $MARK_BEGIN"
    say "# Managed by $NAME. Remove with its uninstall.sh."
    if [[ $TESTED -ne 1 ]]; then
      say "# Untested on this model. Thresholds were tuned on $TESTED_MODEL."
    fi
    cat "$STAGE/quirks.section"
    say "# $MARK_END"
  } >"$STAGE/local-overrides.quirks"
}

do_hypr() {
  say "Hyprland (~/.config/hypr):"
  [[ -f $HYPR_MAIN ]] || die "$HYPR_MAIN not found. This needs Omarchy 4 or newer (Hyprland Lua config). Use --system-only for the /etc part."
  write_file "$HERE/hypr/mac-trackpad.lua" "$HYPR_SNIPPET" user
  if [[ $WITH_OPTIONAL -eq 1 ]]; then
    write_file "$HERE/hypr/mac-trackpad-optional.lua" "$HYPR_OPTIONAL" user
  fi
  stage_hypr_main
  write_file "$STAGE/hyprland.lua" "$HYPR_MAIN" user
  if [[ $WITH_OPTIONAL -ne 1 ]]; then
    remove_file "$HYPR_OPTIONAL" user
  fi
}

do_system() {
  say "System (/etc, needs sudo):"
  stage_quirks
  render "$HERE/etc/udev/hwdb.d/71-apple-t2-trackpad.hwdb" "$STAGE/trackpad.hwdb"
  render "$HERE/etc/udev/rules.d/71-apple-t2-trackpad.rules" "$STAGE/trackpad.rules"
  write_file "$STAGE/local-overrides.quirks" "$QUIRKS_DST" root
  write_file "$STAGE/trackpad.hwdb" "$HWDB_DST" root
  write_file "$STAGE/trackpad.rules" "$RULES_DST" root
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
  if [[ $DO_SYSTEM -eq 1 ]]; then
    resolve_target
    if [[ $TESTED -eq 1 ]]; then
      say "Model: $MODEL, trackpad 05ac:$USB_ID (tested)"
    else
      say "Model: $MODEL, trackpad 05ac:$USB_ID (UNTESTED, forced)"
    fi
  fi
  if [[ $WITH_OPTIONAL -eq 1 ]]; then
    say "Optional laptop-tuned values: yes"
  else
    say "Optional laptop-tuned values: no"
  fi
  say ""

  MODE=plan
  run_steps
  say ""
  if [[ $CHANGED -eq 0 ]]; then
    say "Already installed. Nothing to do."
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
  if [[ $DO_HYPR -eq 1 ]]; then
    say "Hyprland reloads its config on save. If not: hyprctl reload"
  fi
  if [[ $DO_SYSTEM -eq 1 ]]; then
    say "Reboot to apply the /etc part. libinput reads quirks only when the compositor starts."
  fi
}

main "$@"
