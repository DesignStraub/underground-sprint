#!/bin/bash
# ovr.sh WxH  – schreibt override.cfg ins Projekt (randlos, ohne Fokus); ovr.sh off – entfernt sie
P="$(cd "$(dirname "$0")/../.." && pwd)"  # Projektordner (zwei Ebenen über tools/short2)
if [ "$1" = off ]; then rm -f "$P/override.cfg"; exit; fi
printf '[display]\n\nwindow/size/no_focus=true\nwindow/size/borderless=true\nwindow/size/window_width_override=%s\nwindow/size/window_height_override=%s\n\n[editor]\n\nmovie_writer/mjpeg_quality=0.95\n' "${1%x*}" "${1#*x}" > "$P/override.cfg"
