# 概述

- 这是一个为满足自己分享欲并在学习中总结而建立的仓库，当作参考使用，且中内容目的是解决我当前的问题和论坛上看到的一些问题，早期的内容目录结构并不是很完善，文章标题就已经写明了相关问题，方便查看，后续会有所改善。

- 现在主仓库中的是我使用的配置文件，通常适用于最小化安装的 Fedora GNU/Linux 操作系统，主要是 Niri 和 KDE 桌面环境，如果有其他桌面环境也可以尝试使用，因为我使用了极简的登录管理器，如果在安装前有其他登录管理器可以跳过安装。

- 对于使用 Fedora 的新手朋友可以先看一下这一部分[建议](https://github.com/Maomaokuxs/Biyuan-Fedora-Learning/wiki/%E4%BD%BF%E7%94%A8fedora%E7%9A%84%E5%BB%BA%E8%AE%AE)。

- 请前往[wiki](https://github.com/Maomaokuxs/Biyuan-Fedora-Learning/wiki)页面查看。

## 依据

- 基于 《linux 命令行与 shell 脚本编程大全》;
- 基于网络文章；
- 询问 AI 并实践验证，并不是直接复制粘贴到 Wiki。

## 说明

曾经我安装过许多的发行版，我觉得选择发行版确实是一件比较重要的事，我现在已经习惯了使用 Fedora GNU/Linux，最初我都喜欢接受默认，如今倒也开始使用窗口管理器，不知道是不是使用了 Linux 就喜欢简单些，去深究这些功能是怎么实现的，当然我至今依旧是小白，这些脚本是在 AI 的帮助下完成的，由我提出想法经由 AI 去完成，不得不说 Gemini 确实很强，现在主要是 Opencode 配合 Deepseek 使用 。

WIKI 中的内容重要的部分是参照其他的帖子然后自己尝试写下的可行方案，如今为了想要体验 Niri 的用户分享我的配置文件。

## 桌面环境截图

- niri

![niri](images/desktop-screenshot-niri.png)

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

## 仓库脚本文件结构

```text
Biyuan-Fedora-Learning/
├── README.md                    # 安装指引
├── install.sh                   # 安装脚本
├── config/
│   └── repos.list               # 软件仓库清单
│
├── scripts/                     # 【逻辑层】执行脚本
│   ├── by-mgr                   # 核心引擎：备份、部署、系统维护
│   ├── utils.sh                 # 公共工具函数
│   ├── 01_snapper_config.sh     # 基础环境与依赖包安装
│   ├── 02_base_env.sh           # 配置基础环境
│   ├── 03_gpu_drivers.sh        # 配置显卡驱动
│   ├── 04_desktop_niri.sh       # 配置 niri 桌面环境
│   ├── 05_desktop_kde.sh        # 配置 KDE 桌面环境
│   ├── 06_desktop_gnome.sh      # 配置 Gnome 桌面环境
│   └── 07_greetd_setup.sh       # 配置 Greetd/Tuigreet
│
├── dotfiles/                    # 【资产层】配置文件 (Stow 部署)
│   ├── fastfetch/
│   │   └── .config/fastfetch/
│   │       └── config.jsonc     # Fastfetch 系统信息展示
│   ├── hypr/
│   │   └── .config/hypr/
│   │       ├── hypridle.conf    # 空闲监听配置
│   │       └── hyprlock.conf    # 锁屏界面 (由 theme-sync 生成)
│   ├── kitty/
│   │   └── .config/kitty/
│   │       └── kitty.conf       # 终端配置，引入 color-kitty.conf
│   ├── niri/
│   │   └── .config/niri/
│   │       ├── config.kdl       # Niri 核心配置 (平铺、快捷键、启动项)
│   │       ├── keybinds.kdl     # 快键键配置
│   │       └── scripts/
│   │           ├── theme-sync.sh        # 壁纸取色 & 全局配色分发
│   │           ├── wallpaper.sh         # 随机壁纸切换
│   │           ├── wallpaper-picker.sh  # 壁纸选择器
│   │           ├── init-wallpaper.sh    # 初始化壁纸
│   │           └── toggle-theme.sh      # 昼夜模式切换
│   ├── rofi/
│   │   └── .config/rofi/
│   │       ├── config.rasi      # Rofi 全局配置
│   │       ├── scripts/         # 菜单脚本 (powermenu/music/recorder)
│   │       └── themes/          # 主题样式，引入 color-rofi.rasi
│   ├── starship/
│   │   └── .config/
│   │       ├── starship.toml        # 终端提示符 (palette 拼接生成)
│   │       └── starship_base.toml   # Starship 基础模板
│   ├── waybar/
│   │   └── .config/waybar/
│   │       ├── config.jsonc     # Waybar 模块布局
│   │       ├── style.css        # 样式表，引入 color-waybar.css
│   │       └── scripts/         # 模块脚本 (天气/音乐/更新等)
│   ├── xdg-desktop-portal/
│   │   └── .config/xdg-desktop-portal/
│   │       └── niri-portals.conf
│   └── bash/
│       └── .bashrc              # 终端环境变量
│
└── 配色生成路径 (theme-sync.sh 输出)
    ~/.cache/by-mgr/hellwal/
    ├── global-palette.env       # 中央色彩数据库 (唯一数据源)
    ├── color-niri.kdl           # Niri 边框配色
    ├── color-waybar.css         # Waybar 颜色变量
    ├── color-rofi.rasi          # Rofi 颜色变量
    ├── color-kitty.conf         # Kitty 配色 (含 16 色)
    └── color-starship.toml      # Starship palette 切片
```

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
