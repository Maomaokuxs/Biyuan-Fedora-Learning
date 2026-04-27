#!/bin/bash
# File: scripts/07_greetd_setup.sh
# 中文注释：Greetd + Tuigreet 综合部署脚本（支持 NVIDIA/AMD/Intel）

setup_greetd_niri() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}  [Phase 5] Universal Display Manager Setup${NC}"
    echo -e "${BLUE}=====================================================${NC}"

    # --- 1. 安装基础组件 ---
    echo -e "${YELLOW}>> Installing greetd and tuigreet...${NC}"
    sudo dnf install -y greetd tuigreet

    # --- 2. 权限分配 ---
    # 强制指定用户为 greetd，并确保其拥有硬件加速权限
    local g_user="greetd"
    echo -e "${YELLOW}>> Setting hardware permissions for $g_user...${NC}"
    sudo usermod -aG video,render "$g_user"

    # --- 3. 智能内核参数配置 (保持不变，确保 Wayland 兼容性) ---
    local grub_file="/etc/default/grub"
    local updated=false
    echo -e "${BLUE}>> Detecting GPU type for kernel optimization...${NC}"
    
    if lspci | grep -qi "nvidia"; then
        echo -e "${CYAN}>> NVIDIA GPU detected. Applying fixes...${NC}"
        local params="nvidia-drm.modeset=1 nvidia_drm.fbdev=1 ibt=off"
        if ! grep -q "nvidia-drm.modeset=1" "$grub_file"; then
            sudo sed -i "/^GRUB_CMDLINE_LINUX=/ s/\"$/ $params\"/" "$grub_file"
            updated=true
        fi
    elif lspci | grep -qiE "amd|ati"; then
        if ! grep -q "amdgpu.modeset=1" "$grub_file"; then
            sudo sed -i "/^GRUB_CMDLINE_LINUX=/ s/\"$/ amdgpu.modeset=1\"/" "$grub_file"
            updated=true
        fi
    fi

    if [ "$updated" = true ]; then
        echo -e "${YELLOW}>> Rebuilding GRUB configuration...${NC}"
        sudo grub2-mkconfig -o /boot/grub2/grub.cfg
    fi

    # --- 4. 编写启动配置 (根据你的要求修改) ---
    echo -e "${YELLOW}>> Writing /etc/greetd/config.toml...${NC}"
    sudo tee /etc/greetd/config.toml > /dev/null <<EOF
[default_session]
command = "tuigreet --time --cmd /usr/bin/niri"
user = "greetd"

[terminal]
vt = 1
EOF

    # --- 5. 设置启动目标与启用服务 ---
    echo -e "${YELLOW}>> Finalizing system services...${NC}"
    sudo systemctl set-default graphical.target
    sudo systemctl disable gdm sddm lightdm &> /dev/null
    sudo systemctl enable greetd

    echo -e "${GREEN}✅ Greetd deployment complete!${NC}"
}