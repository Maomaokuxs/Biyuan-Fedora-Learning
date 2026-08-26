#!/usr/bin/env python3
import subprocess
import json

def get_metadata():
    try:
        # 获取 标题 和 艺术家
        cmd = ["playerctl", "metadata", "--format", "{{ title }} - {{ artist }}"]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=1)
        status_cmd = ["playerctl", "status"]
        status_result = subprocess.run(status_cmd, capture_output=True, text=True)
        
        text = result.stdout.strip()
        status = status_result.stdout.strip()

        if not text or "No player found" in text:
            return None, "stopped"
        
        return text, status.lower()
    except:
        return None, "stopped"

text, status = get_metadata()

if text:
    # 简单的滚动处理：如果超过 25 字符则截断或处理
    display_text = text if len(text) <= 18 else text[:15] + "..."
    icon = "󰎆" if status == "playing" else "󰏤"
    out = {"text": f"{icon} {display_text}", "class": status}
else:
    out = {"text": "", "class": "stopped"}

print(json.dumps(out))
