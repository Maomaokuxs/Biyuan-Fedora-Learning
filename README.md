# 概述

本仓库是 niri 配置仓库，安装脚本暂时只适合于 Fedora Linux 使用，主要的特色功能是随壁纸切换主要工具的配色，可搭配kde桌面环境使用。

## 说明

- 对于使用 Fedora 的新手朋友可以先看一下这一部分[建议](https://github.com/Maomaokuxs/Biyuan-Fedora-Wiki/blob/main/01-%E5%BF%AB%E9%80%9F%E5%BC%80%E5%A7%8B/%E4%BD%BF%E7%94%A8Fedora%E7%9A%84%E5%BB%BA%E8%AE%AE.md)。

- 请前往[wiki](https://github.com/Maomaokuxs/Biyuan-Fedora-Wiki)页面查看 wiki 内容，对于我的配置文件的使用说明可以直接[跳转](docs/user-guide/README.md)。

- 我至今依旧是小白，这些脚本是在 AI 的帮助下完成的。

## 桌面截图

- niri

![niri](images/desktop-screenshot-niri.png)
![niri](docs/user-guide/images/WallpaperSwitching.gif)

## 安装

- 克隆当前仓库

```bash
git clone https://github.com/Maomaokuxs/Biyuan-Fedora-Learning.git
```

- 授予执行权限

```bash
cd ~/Biyuan-Fedora-Learning
chmod +x ./install.sh
```

- 启动脚本

按照引导安装

```bash
./install.sh
```

## 依据

- 基于 《linux 命令行与 shell 脚本编程大全》;
- 基于网络文章；
- 询问 AI 并测试验证。

## 仓库文件结构

完整目录树与每个配置文件用途见 [docs/user-guide/file-tree.md](docs/user-guide/file-tree.md)。

## 涉及到的部分软件包

- [snapper](https://github.com/openSUSE/snapper)
- [Btrfs-Assistant](https://gitlab.com/btrfs-assistant/btrfs-assistant)
- [grub-btrfs](https://github.com/Antynea/grub-btrfs)
- [dnf5-autosnapper](https://github.com/douglascdev/dnf5-autosnapper)
- [niri](https://github.com/niri-wm/niri)
- [waybar](https://github.com/alexays/waybar)
- [rofi-wayland](https://github.com/in0ni/rofi-wayland)
- [stow](https://github.com/aspiers/stow)
- [fzf](https://github.com/junegunn/fzf)
- [kitty](https://github.com/kovidgoyal/kitty)
- [fastfetch](https://github.com/fastfetch-cli/fastfetch)
- [gwenview](https://github.com/kde/gwenview)
- [hellwal](https://github.com/danihek/hellwal)
- [waypaper](https://github.com/anufrievroman/waypaper)
- [starship](https://github.com/starship/starship)
- [hyprlock](https://github.com/hyprwm/hyprlock)
- [mako](https://github.com/emersion/mako)
- [fcitx5](https://github.com/fcitx/fcitx5)
- [cava](https://github.com/karlstav/cava)
- [dolphin](https://github.com/kde/dolphin)
- [blueman](https://github.com/blueman-project/blueman)
- [btop](https://github.com/aristocratos/btop)
- [kate](https://github.com/kde/kate)
- [ddcutil](https://github.com/rockowitz/ddcutil)
- [nmtui](https://github.com/vimlinuz/nmtui)
- [kwallet](https://github.com/KDE/kwallet)
- [ncdu](https://github.com/rofl0r/ncdu)
- [ranger](https://github.com/ranger/ranger)
- [kde-material-you-colors](https://github.com/luisbocanegra/kde-material-you-colors)
- [playerctl](https://github.com/altdesktop/playerctl)
- [brightnessctl](https://github.com/Hummer12007/brightnessctl)
