if pgrep -x gammastep >/dev/null; then
  pkill gammastep && notify-send "护眼" "已关闭"
else
  if ! command -v gammastep >/dev/null; then
    notify-send "护眼" "gammastep未安装，请安装 gammastep 软件包"
  else
    gammastep -O 4500 >/tmp/gammastep.log 2>&1 &
    sleep 1
    if pgrep -x gammastep >/dev/null; then
      notify-send "护眼" "已开启"
    else
      ERR=$(tail -1 /tmp/gammastep.log 2>/dev/null)
      notify-send "护眼" "启动失败: $ERR"
    fi
  fi
fi
