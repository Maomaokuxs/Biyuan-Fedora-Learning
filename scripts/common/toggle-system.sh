#!/bin/bash
FLAG="$HOME/.cache/by-mgr/waybar_system_hidden"
if [ -f "$FLAG" ]; then rm -f "$FLAG"; else touch "$FLAG"; fi
