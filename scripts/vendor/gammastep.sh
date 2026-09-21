#!/bin/bash
if [ -f ~/.cache/by-mgr/waybar_left_hidden ]; then echo '{"text":"","class":"hidden"}'; exit 0; fi
if pgrep -x gammastep >/dev/null; then echo '{"text":"󰖃","tooltip":"护眼已开启"}'; else echo '{"text":"󰖃","tooltip":"护眼已关闭"}'; fi
