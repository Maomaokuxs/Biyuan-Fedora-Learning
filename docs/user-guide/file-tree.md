# 仓库文件结构：完整目录树 + 逐文件说明

> 布局：顶层按 `config / scripts / src / dotfiles / docs / notes / assets` 划分；
> `dotfiles/` 一应用一目录，经 Stow 部署到 `~/`；`scripts/01~07` 装机，`src/by-mgr-*` 管理工具；
> 配色由 `theme-sync.sh` 统一分发。`（生成物）` 表示每次运行自动重写，勿手改。

```text
.
├── assets
│   ├── fonts
│   │   ├── IosevkaNerdFont-Regular.ttf
│   │   ├── LICENSE.md
│   │   └── SarasaTermSC-SemiBold.ttf
│   └── wallpapers
│       ├── default_wallpaper.jpg
│       ├── wallpaper1.png
│       └── wallpaper2.jpg
├── config
│   └── repos.list
├── docs
│   └── user-guide
│       ├── images/ (文档配图)
│       ├── user-guide.md (使用帮助)
│       └── file-tree.md (本文件)
├── dotfiles
│   ├── by-mgr/.config/by-mgr
│   │   ├── templates/ (config_base、starship_base.toml)
│   │   └── weather.conf
│   ├── fastfetch/.config/fastfetch/config.jsonc
│   ├── hypr/.config/hypr
│   │   ├── scripts/sleep-safe.sh
│   │   ├── hypridle.conf
│   │   └── hyprlock.conf
│   ├── kitty/.config/kitty/kitty.conf
│   ├── mako/.config/mako
│   │   ├── config (生成物) / config_base (模板)
│   ├── niri/.config/niri
│   │   ├── scripts/ (8 个，见下)
│   │   ├── config.kdl / keybinds.kdl / niri-outputs.kdl
│   ├── plasma-apply-colorscheme/.local/bin/plasma-apply-colorscheme
│   ├── quickshell/.config/quickshell
│   │   ├── bar/ (5 个) / components/ (24 个) / dock/Dock.qml
│   │   ├── scripts/ (common/ 等)
│   │   ├── styles/duo/shell.qml
│   │   └── shell.qml / Theme.qml
│   ├── rofi/.config/rofi
│   │   ├── scripts/ (powermenu/music/recorder)
│   │   ├── themes/ (current/powermenu/musicmenu.rasi)
│   │   └── config.rasi
│   ├── starship/.config/starship_base.toml
│   ├── waybar/.config/waybar
│   │   ├── scripts/ (18 个，见下)
│   │   ├── config.jsonc / modules.common.jsonc
│   │   └── style_base.css (模板) / style.css (生成物) / color-waybar.css (生成物)
│   ├── waypaper/.config/waypaper/config.ini
│   └── xdg-desktop-portal/.config/xdg-desktop-portal/portals.conf
├── images
│   └── desktop-screenshot-niri.png
├── notes
│   ├── CHANGELOG.md / ROADMAP.md
├── scripts
│   ├── 01_snapper_config.sh ~ 07_greetd_setup.sh
│   ├── by-mgr (编译好的管理工具) / utils.sh
├── src
│   ├── by-mgr-legacy/ (by-mgr.sh + lib/ 9 个)
│   └── by-mgr-rs/ (Cargo.toml + src/)
├── install.sh / README.md / LICENSE / .gitignore
```

## 逐文件说明

**顶层**：`install.sh` 装机总入口；`README.md` 安装指引；`LICENSE` 许可证；`.gitignore` 忽略规则。
`config/repos.list` 软件源清单（by-mgr 初始化 `~/.config/by-mgr/repos.list` 用）。
`images/desktop-screenshot-niri.png` 桌面效果图；`notes/CHANGELOG.md` 变更记录；`notes/ROADMAP.md` 路线图。
`assets/fonts/` 终端/中文等宽字体；`assets/wallpapers/` 默认壁纸库（`default_wallpaper.jpg` 为缺省项）。
`docs/user-guide/user-guide.md` 使用帮助正文；`images/` 文档配图。

**scripts/（装机）**：`01_snapper_config.sh` 快照与基础依赖；`02_base_env.sh` 基础环境；
`03_gpu_drivers.sh` 显卡驱动；`04_desktop_niri.sh` niri 桌面（含模板部署）；
`05_desktop_kde.sh` KDE；`06_desktop_gnome.sh` GNOME；`07_greetd_setup.sh` 登录管理器；
`utils.sh` 公共函数；`by-mgr` 编译好的管理工具。

**src/by-mgr-legacy（bash 版）**：`by-mgr.sh` 主菜单；`lib/clean.sh` 清旧快照；`lib/deploy.sh` 部署配置；
`lib/display.sh` 显示器管理；`lib/editor.sh` 编辑器调用；`lib/ota.sh` 在线更新；`lib/repo.sh` 软件源清单维护；
`lib/restore.sh` 还原（含壁纸/配色）；`lib/snapshot.sh` 快照到 `~/.config/by-mgr/backup/`；`lib/utils.sh` 公共函数。
**src/by-mgr-rs（Rust 重构）**：`main.rs` 入口；`config.rs` 路径配置；`sudo.rs` 提权；
`core/` 与 legacy 同名功能一一对应；`ui/app.rs` ratatui 主界面；`ui/theme.rs` 主题预览（读中央配色库）。

**dotfiles/niri**：`config.kdl` 主配置（布局/自启栏与后台）；`keybinds.kdl` 空占位（键位由 niri-settings 接管）；
`niri-outputs.kdl` 显示器配置；`scripts/theme-sync.sh` 取色→中央库→11 应用分发→热重载；
`scripts/init-wallpaper.sh` 首次导入壁纸（一次性锁）；`scripts/wallpaper.sh` 随机换壁纸；
`scripts/wallpaper-picker.sh` rofi 选壁纸；`scripts/toggle-theme.sh` 手动昼夜切换；
`scripts/toggle-bar.sh` 顶栏一键切换；`scripts/quickshell-launch.sh` 按记录启动顶栏风格；
`scripts/niri-kitty-decor.sh` 隐藏 kitty 标题栏。

**dotfiles/waybar**：`config.jsonc` 双屏模块布局；`modules.common.jsonc` 全模块定义；
`style_base.css` 样式模板；`style.css` 生成物（勿手改）；`color-waybar.css` 取色生成物；
`scripts/auto-theme.sh` 昼夜自动（6-18 点+2 小时手动锁）；`scripts/toggle-left.sh` 藏左侧工具；
`scripts/toggle-music.sh` 藏音乐控件；`scripts/toggle-system.sh` 藏系统组；`scripts/toggle-lyric.sh` 歌词开关；
`scripts/music.py` 歌名；`scripts/lyric.py` 酷狗歌词行；`scripts/cava.sh` 频谱（PipeWire/Pulse 自选后端）；
`scripts/weather.py` 天气（失败不覆盖缓存+退避）；`scripts/check-updates.sh` 可更新包数；
`scripts/brightness.sh` 内屏亮度；`scripts/powerprofiles.sh` 性能模式；`scripts/inhibit.sh` 熄屏抑制；
`scripts/gammastep.sh` 护眼；`scripts/screen.sh` 屏幕模式（Win+P 式）；`scripts/screenshot.sh` 截图；
`scripts/pick-color.sh` 取色器；`scripts/fcitx_status.sh` 输入法状态。

**dotfiles/quickshell**：`shell.qml` 双屏顶栏+dock 入口；`Theme.qml` 跟随壁纸主题；
`styles/duo/shell.qml` 双岛实验风格；`bar/Bar.qml` 顶栏组装（含天气 `FileView` 即时刷）；
`bar/Workspaces.qml` 工作区；`bar/LevelMeter.qml` 音量表；`bar/SpectrumMeter.qml` 真频谱柱；
`bar/DanceMeter.qml` 律动动画；`components/Pill.qml` 通用色块；`components/ScriptPill.qml` shell 轮询 pill；
`components/BarState/PaletteState/SpectrumState/UiState.qml` 共享状态单例；
`components/Exec/Icons.qml` 路径与图标常量；`components/Audio/Battery/BluetoothPill.qml` 设备 pills；
`components/MprisButton/MprisSelect/MediaPlayer/MusicInfo.qml` 媒体 pills；
`components/VolCard/BriCard/SliderBar.qml` 控制卡；`components/VizCard.qml` 可视化卡；
`components/WallpaperCard.qml` 壁纸卡；`components/ControlCenter.qml` 控制中心浮窗；
`components/NotifCenter/Notifs/Toasts.qml` 通知中心三件套；`dock/Dock.qml` 底部浮动 dock；
`scripts/dock-ensure-stash/minimize/restore/state.sh` 窗口收纳四件套；
`scripts/common/` 跨栏复用脚本（与 waybar 同名功能一致，`weather.py` 逐字同步）；
`scripts/common/tray-open.py` 托盘左键聚焦通用链；`scripts/common/toggle-music-tail.sh` 只藏音乐跟随者；
`scripts/common/lyric-guard.sh` 无播放免启动守卫；`scripts/spectrum.py` 12 柱频谱源；
`scripts/wallthumbs.sh` 壁纸缩略图；`scripts/bar-fast.sh` 快查聚合；
`scripts/brightness.sh` 内屏亮度；`scripts/brightness-external.sh` 外屏亮度查询；
`scripts/brightness-set.sh` 设置亮度；`scripts/cpu/memory/network/bluetooth/audio/battery.sh` 各 pill 数据源；
`scripts/inhibit.sh` 熄屏抑制；`scripts/left-visibility.sh` 左侧显隐字形；
`scripts/fcitx5/sync-waybar.sh` 按配色生成输入法皮肤；`scripts/fcitx5/hud-paper*/` 浅深两套皮肤资源。

**dotfiles/rofi**：`config.rasi` 全局配置；`themes/current.rasi` 主题；
`themes/powermenu.rasi` 电源菜单主题；`themes/musicmenu.rasi` 音乐菜单主题（均引用取色）；
`scripts/powermenu.sh` 电源菜单（锁→睡降级链）；`scripts/powermenu.sh.bak` 备份垃圾可删；
`scripts/music-menu.sh` 音乐控制台；`scripts/recorder.sh` 录屏启停。

**其他应用**：`kitty/kitty.conf` 终端（透明模糊+引用取色）；
`hypr/hypridle.conf` 300 锁/600 熄/900 睡+唤醒刷天气；`hypr/scripts/sleep-safe.sh` 休眠→挂起→熄屏降级；
`hypr/hyprlock.conf` 取色生成物（多屏锁屏）；`mako/config_base` 通知样式模板；`mako/config` 生成物；
`starship/starship_base.toml` 提示符模板（取色拼接）；`fastfetch/config.jsonc` 系统信息展示；
`waypaper/config.ini` 壁纸源+换后回调取色；`xdg-desktop-portal/portals.conf` 文件选择走 KDE 门户；
`plasma-apply-colorscheme` 非 KDE 下的配色兼容脚本；`by-mgr/templates/` 配置模板；
`by-mgr/weather.conf` 天气地点编码（本地持久化，不进仓库）。
