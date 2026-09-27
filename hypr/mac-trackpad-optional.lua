-- OPTIONAL. Not installed unless you pass --with-optional to install.sh.
--
-- These values were tuned by feel on one MacBookPro16,1 (2019 16-inch).
-- They are taste, not fixes. On another Mac treat them as a starting point:
-- the pad size, the device name, and your fingers all differ.

-- Scroll speed outside browsers. Omarchy ships 0.4, Hyprland ships 1.0.
-- 1.0 was way too fast on this T2 pad. 0.3 is a bit slower than Omarchy.
-- Same knob for vertical and horizontal; Hyprland has no axis-specific
-- scroll_factor. Browsers stay at 0.1 via the rules in mac-trackpad.lua.
hl.config({
  input = {
    touchpad = {
      scroll_factor = 0.3,
    },
  },
})

-- MacBookPro16,1 T2 trackpad (hid-magicmouse, ~96 units/mm, 160x100mm).
-- Hyprland clamps sensitivity to 1.0 and adaptive still decelerates slow
-- moves (~0.3x) with libinput's extra touchpad slowdown (~0.4x), which is
-- why max sensitivity still feels like dragging through mud.
--
-- Custom profile points are output velocity, not multipliers. The first
-- number is the step between points (0.5 units/ms). A curve that ends too
-- early gets extrapolated, and typical finger motion on this pad is 2-30
-- units/ms, so a short curve makes flicks explode.
--
-- Pointer curve is xuanping.trackpad's macOS pack, retargeted to this
-- T2 device. Crawl kept (~0.10x). Flick cap ~1.15x. The last two points
-- hold that slope past 10.5 units/ms. Scroll stays 1:1.
--
-- The name must match your device. Check with: hyprctl devices
hl.device({
  name = "apple-inc.-apple-internal-keyboard-/-trackpad-1",
  accel_profile = "custom 0.5 0.0 0.05 0.11 0.195 0.32 0.494 0.735 1.06 1.488 2.05 2.775 3.69 4.83 6.235 7.16 7.92 8.73 9.62 10.35 10.93 11.50 12.08",
  -- 1:1 scroll so two-finger scrolling does not pick up the pointer curve.
  scroll_points = "1.0 0.0 1.0 2.0 3.0 4.0",
  tap_to_click = true,
  tap_and_drag = false,
  clickfinger_behavior = true,
})
