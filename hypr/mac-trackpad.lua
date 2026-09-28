-- Mac-style trackpad behavior for Hyprland on Omarchy 4 (Lua config).
--
-- Installed to ~/.config/hypr/mac-trackpad.lua and loaded from the end of
-- ~/.config/hypr/hyprland.lua, so these values win over Omarchy's defaults
-- and over anything in your own input.lua.
--
-- Nothing in this file is tied to one Mac model. Values tuned by feel on a
-- single laptop (pointer curve, scroll_factor) live in
-- mac-trackpad-optional.lua and are not installed by default.

hl.config({
  input = {
    touchpad = {
      -- One-finger tap = left click. Two-finger tap = right click.
      tap_to_click = true,
      -- A tap followed by a hold does not start a drag. Drags need a press.
      tap_and_drag = false,
      -- Ignore the pad while keys are going down.
      disable_while_typing = true,
      -- Traditional direction (finger down, page down). Set true for the
      -- macOS "natural" direction.
      natural_scroll = false,
      -- Press with 1/2/3 fingers = left/right/middle click. The bottom
      -- right corner stays a left click.
      clickfinger_behavior = true,
    },
  },
})

-- Chromium on Wayland over-scales high-res Apple trackpad scroll relative
-- to other apps. Hyprland regexes must fully match the class, so [bB]rave
-- does not hit class "brave-browser". Match Omarchy's browser tags instead,
-- plus Brave PWA classes (brave-x.com__-Default) that may be untagged.
-- scroll_touchpad replaces input.touchpad.scroll_factor for these windows.
o.window({ tag = "chromium-based-browser" }, { scroll_touchpad = 0.1 })
o.window({ tag = "firefox-based-browser" }, { scroll_touchpad = 0.1 })
o.window(".*[Bb]rave.*", { scroll_touchpad = 0.1 })

-- The three-finger swipe lives in mac-trackpad-gesture.lua. install.sh
-- skips it when your config already has one, because Hyprland reports a
-- second identical gesture as a config error.
