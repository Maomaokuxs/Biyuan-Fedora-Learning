#!/bin/bash
# sleep-safe.sh — 安全睡眠：休眠前检查支持度，不支持则降级
# 优先级：hibernate（需物理 swap + resume= 内核参数）> suspend（需 /sys/power/state 有 mem）> 熄屏保底
# 供 hypridle 与 powermenu 共用，避免无休眠配置的机器锁后一直亮屏

has_physical_swap() {
    # 排除 zram，zram 不能用于休眠
    swapon --show --noheadings 2>/dev/null | grep -v "zram" | grep -q .
}

has_resume_param() {
    grep -q "resume=" /proc/cmdline 2>/dev/null
}

can_mem_sleep() {
    grep -q "mem" /sys/power/state 2>/dev/null
}

if has_physical_swap && has_resume_param; then
    systemctl hibernate && exit 0
fi

if can_mem_sleep; then
    systemctl suspend && exit 0
fi

# 保底：连挂起都不支持时至少熄屏，不让锁屏后一直亮着
niri msg action power-off-monitors 2>/dev/null
exit 1
