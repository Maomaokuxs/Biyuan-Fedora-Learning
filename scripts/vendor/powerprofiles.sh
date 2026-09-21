#!/bin/bash
# 用户态免密性能切换（Fedora）
# 使用方式：
#   - 依赖 power-profiles-daemon（sudo dnf --allowerasing install power-profiles-daemon && systemctl enable --now power-profiles-daemon）
#   - 与 tuned-ppd 冲突，二选一；powerprofilesctl 经 polkit 对 active 用户免密
#   - SELinux 检查：ls -Z /usr/sbin/powerprofilesctl → bin_t，daemon → powerprofiles_exec_t；异常时 sudo restorecon -Rv /usr/libexec/power-profiles-daemon
#   - 行为：powerprofilesctl get/set 循环 performance→balanced→power-saver，无 daemon 时回落 tuned 展示
if command -v powerprofilesctl >/dev/null 2>&1; then
  prof=$(powerprofilesctl get 2>/dev/null || echo "balanced")
  case "$1" in
    toggle)
      case "$prof" in
        performance) powerprofilesctl set balanced ;;
        balanced) powerprofilesctl set power-saver ;;
        power-saver) powerprofilesctl set performance ;;
        *) powerprofilesctl set balanced ;;
      esac
      prof=$(powerprofilesctl get 2>/dev/null)
      cn=$prof; [ "$prof" = "performance" ] && cn="高性能"; [ "$prof" = "balanced" ] && cn="均衡"; [ "$prof" = "power-saver" ] && cn="节能"
      notify-send "性能模式" "$cn"
      ;;
    *)
      case "$prof" in
        performance) icon="󰓅" ;;
        power-saver) icon="󰾆" ;;
        *) icon="󰾅" ;;
      esac
      cn=$prof; [ "$prof" = "performance" ] && cn="高性能"; [ "$prof" = "balanced" ] && cn="均衡"; [ "$prof" = "power-saver" ] && cn="节能"
      echo "{\"text\":\"$icon\",\"tooltip\":\"当前: $cn\\n点击切换\"}"
      ;;
  esac
else
  prof=$(tuned-adm active 2>/dev/null | awk '{print $NF}')
  cn=$prof; [ "$prof" = "powersave" ] && cn="节能"; [ "$prof" = "balanced" ] && cn="均衡"; [ "$prof" = "throughput-performance" ] && cn="高性能"
  case "$prof" in powersave) icon="󰾆";; balanced) icon="󰾅";; *) icon="󰓅";; esac
  echo "{\"text\":\"$icon\",\"tooltip\":\"当前: $cn (tuned)\"}"
fi
