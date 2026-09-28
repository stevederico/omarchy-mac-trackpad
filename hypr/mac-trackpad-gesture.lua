-- Three-finger horizontal swipe: macOS swipe between desktops.
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Gestures/
--
-- install.sh only loads this file when no other file in ~/.config/hypr
-- already defines a three-finger horizontal gesture. A second one is a
-- Hyprland config error ("Gesture will be overshadowed").
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
