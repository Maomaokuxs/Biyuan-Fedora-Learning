#!/bin/bash

# 获取当前的颜色模式
CURRENT=$(gsettings get org.gnome.desktop.interface color-scheme)

if [ "$CURRENT" == "'prefer-dark'" ]; then
    # 切换到浅色（日间）
    gsettings set org.gnome.desktop.interface color-scheme 'default'
    # 如果你还需要切换 GTK 主题名称，可以取消下方注释并修改为你安装的主题
    # gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita'
else
    # 切换到深色（夜间）
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
    # gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark'
fi
