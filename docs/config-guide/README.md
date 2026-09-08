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

1. `Check and pull the latest remote code? (y/N):` → `y` 拉取/`N` 跳过
2. `Create snapper snapshot? (y/N):` → `y` 创建 `Btrfs` 快照/`N` 跳过（仅 `Btrfs`）
3. `Select [1-4 / r / n]:` 选镜像（`1 Tuna`/`2 Aliyun`/`3 USTC`/`4 Cernet`，`r` 恢复官方，`n` 保持）
4. `Install NVIDIA drivers? (y/N):` → `y` 装 `rpmfusion` 显卡驱动/`N` 跳过
5. 后续 `Install niri? (y/N)` / `Install KDE? (y/N)` / `Install Greetd? (y/N)` 等桌面选择均 `y` 安装/`N` 跳过

## 4. waybar天气模块配置

```bash
echo "LOCATION=Shanghai" > ~/.config/by-mgr/weather.conf
```
