#!/bin/bash
FLAG="/tmp/waybar_system_hidden"
if [ -f "$FLAG" ]; then rm -f "$FLAG"; else touch "$FLAG"; fi
