# omarchy-mac-trackpad

Make the built-in trackpad on an Intel T2 MacBook feel right on [Omarchy](https://omarchy.org).

Out of the box the T2 trackpad works, but a graze moves the cursor, a resting thumb freezes the pointer, and palm rejection is off because Linux thinks the pad is an external USB device. This repo fixes those and sets Mac-style clicks and gestures.

## What you get

- Tap to click. Two-finger tap or two-finger press for right click.
- Three-finger swipe left and right to switch workspaces.
- No cursor jumps from a light graze.
- A thumb resting on the pad no longer turns a one-finger move into a scroll.
- Palm rejection that treats the pad as part of the laptop.
- Slower, saner scrolling in browsers.
- Optional: a pointer curve and scroll speed tuned on a 16-inch MacBook Pro.

## Which Macs it fits

| Model | Machine | Trackpad USB id | Status |
|-------|---------|-----------------|--------|
| MacBookPro16,1 | 16-inch, 2019 | 05ac:0340 | Tested. See below. |
| MacBookPro16,2 | 13-inch, 2020, four ports | 05ac:027e | Untested |
| MacBookPro16,3 | 13-inch, 2020, two ports | 05ac:027f | Untested |
| MacBookPro15,1 | 15-inch, 2018 and 2019 | 05ac:027c | Untested |
| MacBookPro15,1 (some units) | 15-inch, 2018 and 2019 | 05ac:0278 | Untested |
| MacBookPro15,2 | 13-inch, 2018 and 2019, four ports | 05ac:027b | Untested |
| MacBookPro15,4 | 13-inch, 2019, two ports | 05ac:027d | Untested |
| MacBookAir8,1 | 2018 | 05ac:027a | Untested |
| MacBookAir9,1 | 2020 | 05ac:0280 | Untested |

Every value here was tuned on one MacBookPro16,1. The USB ids come from the Linux kernel (`WELLSPRINGT2_*` in `drivers/hid/hid-ids.h`).

What "tested" means on the MacBookPro16,1:

- The Hyprland values, the udev files, and all quirks except `AttrThumbSizeThreshold` are in daily use
- `AttrThumbSizeThreshold=1100` has not been used day to day yet
- The installer found the model and trackpad id by itself, and its dry run was correct
- The test suite passed on the machine
- Install then uninstall, run against copies of the machine's real files, gave back identical files
- A real install into `/etc` on that machine has not been done yet

On any other T2 model the installer stops unless you pass `--force`. With `--force` it rewrites the matches to your model and your trackpad's USB id, which it reads from the live device, and drops the 16-inch size hint. The thresholds stay the same. They are a starting point on a smaller pad, not a promise. T2 models missing from the table (MacBookPro15,3, MacBookPro16,4, MacBookAir8,2) work the same way.

Not for Apple Silicon Macs or for Intel Macs without a T2 chip. Older Intel MacBooks also have USB trackpads, but with ids that are not in the T2 list above, so the installer refuses the `/etc` part there even with `--force`. The Hyprland part still works with `--hypr-only`.

## Requirements

- Omarchy 4 or newer. Hyprland is configured in Lua (`~/.config/hypr/hyprland.lua`).
- A kernel with T2 support, which you already have if the trackpad works at all.

## Install

```bash
git clone https://github.com/stevederico/omarchy-mac-trackpad.git
cd omarchy-mac-trackpad
./install.sh --dry-run   # look first, changes nothing
./install.sh
```

The installer prints a diff of every file it will touch, then asks. Run it as your own user. It calls `sudo` itself, and only for the three files under `/etc` and the udev/hwdb reload. It asks for the sudo password before writing anything, so a failed sudo cannot leave a half install.

Reboot afterwards. libinput reads its quirks only when the compositor starts, so a Hyprland reload is not enough for the `/etc` part.

| Option | What it does |
|--------|--------------|
| `-n`, `--dry-run` | Show what would change. Touch nothing. |
| `-y`, `--yes` | Apply without asking. |
| `--with-optional` | Also install the laptop-tuned pointer curve and scroll speed. |
| `--hypr-only` | Only the Hyprland part. No sudo. |
| `--system-only` | Only the `/etc` part. |
| `--model NAME` | Mac model. Default: read from DMI. |
| `--usb-id XXXX` | Trackpad USB product id. Default: read from the device. |
| `--force` | Install the `/etc` part on an untested model. |

Running it again is safe. If nothing differs it says so and stops. The install always matches the flags you pass, so running it again without `--with-optional` removes the optional values.

After `omarchy-refresh-hyprland`, run `./install.sh` again. That command resets `~/.config/hypr/hyprland.lua` to the Omarchy default, which drops the `require` lines this tool added.

## What it changes

| File | Change |
|------|--------|
| `~/.config/hypr/mac-trackpad.lua` | New file. |
| `~/.config/hypr/mac-trackpad-gesture.lua` | New file, skipped if you already have a three-finger swipe. |
| `~/.config/hypr/mac-trackpad-optional.lua` | New file, only with `--with-optional`. |
| `~/.config/hypr/hyprland.lua` | A marked block of `require` lines added at the end. |
| `/etc/libinput/local-overrides.quirks` | A marked block added. Other sections are kept. |
| `/etc/udev/hwdb.d/71-apple-t2-trackpad.hwdb` | New file. |
| `/etc/udev/rules.d/71-apple-t2-trackpad.rules` | New file. |

After writing the `/etc` files it runs `systemd-hwdb update` and `udevadm control --reload`.

Every file that gets changed or replaced is copied first to `~/.local/state/omarchy-mac-trackpad/backups/<timestamp>.<pid>/`.

If a file in `~/.config/hypr` already has a three-finger horizontal gesture, the installer leaves yours alone and skips its own. Hyprland reports two identical gestures as a config error. Browser scroll rules you already have are harmless, but you can drop them.

## Uninstall

```bash
./uninstall.sh --dry-run
./uninstall.sh
```

This removes the marked blocks and the files the installer created. Anything else in `hyprland.lua` or the quirks file stays, byte for byte. `hyprland.lua` itself is never deleted, even if the block was all it held. If install replaced udev files that were already there, uninstall puts them back from the backup. udev files with the same name that this tool did not install are left alone unless you pass `--force`.

## What each setting does

### Hyprland: `hypr/mac-trackpad.lua`

| Setting | Value | Effect |
|---------|-------|--------|
| `tap_to_click` | `true` | One-finger tap is a left click. Two-finger tap is a right click. |
| `tap_and_drag` | `false` | Tap then hold does not start a drag. Drags need a real press, so stray taps do not move windows or select text. |
| `disable_while_typing` | `true` | The pad is ignored while keys are going down. |
| `natural_scroll` | `false` | Traditional direction. Set `true` for the macOS direction. |
| `clickfinger_behavior` | `true` | Press with one, two, or three fingers for left, right, or middle click. No corner zones. |
| `scroll_touchpad` (browser windows) | `0.1` | Chromium and Firefox scroll far too fast with a high-resolution Apple pad. This slows them down without touching other apps. |
| three-finger gesture (`mac-trackpad-gesture.lua`) | horizontal, `workspace` | Swipe between workspaces like macOS desktops. |

### libinput: `etc/libinput/local-overrides.quirks`

Sizes are raw touch units from the trackpad. The range is 0 to 5000.

| Setting | Value | Effect |
|---------|-------|--------|
| `AttrTouchSizeRange` | `300:240` | A contact counts as a touch at 300 and ends below 240. The stock Apple value is `150:130`, low enough that a graze still moves the cursor. |
| `AttrThumbSizeThreshold` | `1100` | A contact this big is a thumb. A resting thumb then stops counting as a second finger, so it does not start a two-finger scroll and freeze the pointer. |
| `AttrPalmSizeThreshold` | `1600` | A contact this big is a palm and is ignored. Same as the stock Apple USB value. |
| `AttrSizeHint` | `160x100` | The real size of the 16-inch pad in mm. The stock value is `104x75`. Only installed on MacBookPro16,1. |

The order matters: touch (300) is below thumb (1100), which is below palm (1600).

### udev: `etc/udev/hwdb.d/` and `etc/udev/rules.d/`

The T2 chip presents the built-in trackpad as a USB device, so udev marks it as external. libinput then skips the palm detection it uses for laptop touchpads. Both files set `ID_INPUT_TOUCHPAD_INTEGRATION=internal` for the trackpad.

The hwdb entry is the standard way. The rule sets the same property directly and runs after systemd's `70-touchpad.rules`, so the result holds even if the hwdb lookup misses.

## Optional values

`hypr/mac-trackpad-optional.lua` is only installed with `--with-optional`. These are taste, tuned by feel on one MacBookPro16,1.

| Setting | Value | Effect |
|---------|-------|--------|
| `scroll_factor` | `0.3` | Scroll speed outside browsers. Omarchy ships `0.4`. |
| `accel_profile` | custom curve | Pointer speed curve. Slow and precise at a crawl, close to 1:1 on a flick. |
| `scroll_points` | 1:1 | Keeps two-finger scrolling from picking up the pointer curve. |

The curve is attached to the device by name: `apple-inc.-apple-internal-keyboard-/-trackpad-1`. Check yours with `hyprctl devices` and edit the file if it differs. If the name does not match, the curve is ignored.

## Check that it worked

The `libinput` debug commands need the debug tools:

```bash
sudo pacman -S libinput-tools python-libevdev python-pyudev
```

```bash
# Find the trackpad's event node
sudo libinput list-devices | grep -A1 -i trackpad

# Should print ID_INPUT_TOUCHPAD_INTEGRATION=internal
udevadm info /dev/input/eventN | grep INTEGRATION

# Should list the thresholds above
sudo libinput quirks list /dev/input/eventN

# Should print true
hyprctl getoption input:touchpad:tap_to_click
hyprctl configerrors
```

## Tune it yourself

Hands differ. If a light touch is ignored, lower the first number in `AttrTouchSizeRange`. If a resting thumb still scrolls, lower `AttrThumbSizeThreshold`.

To see the sizes your own fingers produce:

```bash
sudo libinput measure touch-size /dev/input/eventN
```

Edit the block in `/etc/libinput/local-overrides.quirks`, then reboot. Running `install.sh` again puts the shipped values back.

## Tests

```bash
shellcheck -x install.sh uninstall.sh lib/common.sh test/run.sh
./test/run.sh
```

`test/run.sh` runs the real install and uninstall against a throwaway home directory and a fake `/etc`. It never writes to the live system, never runs the real sudo, and never reloads udev. The sudo failure test puts a fake `sudo` first in `PATH`.

## License

MIT. See [LICENSE](LICENSE).

## Credits

The first 14 points of the optional pointer curve come from `MACOS_ACCEL` in `lib/trackpad.py` of [xuanping.trackpad](https://github.com/lxp-git/omarchy-trackpad), used under the MIT License:

> Copyright (c) 2026 xuanping
>
> Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
