# 配置文件使用说明（从零开始）

## 1. 克隆与预览

```bash
git clone https://github.com/Maomaokuxs/Biyuan-Fedora-Learning.git
cd Biyuan-Fedora-Learning
```

## 2. 安装

```bash
chmod +x install.sh
./install.sh
```

1. `Check and pull the latest remote code? (y/n):` → `y` 拉取/`n` 跳过
2. `Create snapper snapshot? (y/n):` → `y` 创建 `Btrfs` 快照/`n` 跳过（仅 `Btrfs`）
3. `Select [1-4 / r / n]:` 选镜像（`1 Tuna`/`2 Aliyun`/`3 USTC`/`4 Cernet`，`r` 恢复官方，`n` 保持）
4. `Install NVIDIA drivers? (y/n):` → `y` 装 `rpmfusion` 显卡驱动/`n` 跳过
5. 后续 `Install niri? (y/n)` / `Install KDE? (y/n)` / `Install Greetd? (y/n)` 等桌面选择均 `y` 安装/`n` 跳过

## 3.使用

1. bar
  
    - 介绍

      bar 我使用了两款，功能大致是相同的，分别是 waybar 和 quickshell，想要启用哪款只要在 niri 配置文件中取消注释，记得只启用一款，以下针对的是我的配置文件说明非软件本身的拉踩。

      waybar：优点是资源占用小，启动速度快，缺点就是动画简单没有那么华丽。

      ![waybar](docs/config-guide/waybar.png)

      quickshell：优点是扩展丰富，并且本身就支持弹窗，非常的方便，动画更加优雅，缺点是占用比waybar高。

      ![quickshell](quickshell.png)

    - 使用

      - 隐藏工具栏

        右键点击左侧 Fedora 徽标，或电源开关

        ![HideTools](HideTools.gif)

## 4. waybar天气模块配置

```bash
echo "LOCATION=Shanghai" > ~/.config/by-mgr/weather.conf
```
