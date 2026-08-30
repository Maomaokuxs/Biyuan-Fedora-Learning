#!/usr/bin/env python3
import json
import os
import sys
import time
import subprocess
import requests

# 清除代理环境变量：天气定位/请求走真实网络，避免代理出口导致的定位错误
for k in ("http_proxy", "https_proxy", "all_proxy", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY"):
    os.environ.pop(k, None)

CACHE = os.path.expanduser("~/.cache/by-mgr/weather.json")
FRESH_SECONDS = 1800  # 30 分钟内视为新鲜
SIGNAL = "RTMIN+10"   # 后台刷新完成后通知 waybar 重新执行本脚本

CONF = os.path.expanduser("~/.config/by-mgr/weather.conf")

# 时区 → 城市 映射（系统时区不受代理影响，默认走这里）
TZ_CITY = {
    "Asia/Shanghai": "Shanghai", "Asia/Chongqing": "Chongqing", "Asia/Guangzhou": "Guangzhou",
    "Asia/Tokyo": "Tokyo", "Asia/Seoul": "Seoul", "Asia/Singapore": "Singapore",
    "Asia/Hong_Kong": "Hong Kong", "Asia/Taipei": "Taipei", "Asia/Kolkata": "New Delhi",
    "Europe/London": "London", "Europe/Paris": "Paris", "Europe/Berlin": "Berlin",
    "Europe/Moscow": "Moscow", "America/New_York": "New York", "America/Chicago": "Chicago",
    "America/Los_Angeles": "Los Angeles", "America/Sao_Paulo": "Sao Paulo",
    "Australia/Sydney": "Sydney", "Australia/Perth": "Perth",
}

def read_conf():
    """读取可选配置文件 weather.conf，格式: LOCATION=城市名"""
    try:
        with open(CONF) as f:
            for line in f:
                line = line.strip()
                if line.startswith("LOCATION="):
                    v = line.split("=", 1)[1].strip()
                    if v:
                        return v
    except Exception:
        pass
    return ""

def tz_city():
    """系统时区 → 城市（不受代理影响）"""
    try:
        tz = subprocess.run(["timedatectl", "show", "-p", "Timezone", "--value"],
                            capture_output=True, text=True, timeout=3).stdout.strip()
        return TZ_CITY.get(tz, "")
    except Exception:
        return ""

def get_location():
    """三层定位：配置文件 > 系统时区 > IP(仅兜底)"""
    loc = read_conf()
    if loc:
        return loc
    loc = tz_city()
    if loc:
        return loc
    try:
        r = requests.get("http://ip-api.com/json", timeout=5)
        j = r.json()
        if j.get("status") == "success" and j.get("city"):
            return j["city"]
    except Exception:
        pass
    return ""

def fetch_weather():
    """实时拉取并返回结果 dict"""
    try:
        headers = {'User-Agent': 'Mozilla/5.0'}
        loc = get_location()
        # 国内免 key：优先 sojson（需城市编码），编码由本地 weather.conf 的 LOCATION 决定，未配置编码则走 wttr.in 兜底（支持任意城市名）
        # 本地编码文件 weather.conf 可追加 CITY_CODE=101240707 形式，或直接用 wttr.in 无需编码
        code = ""
        try:
            with open(CONF) as f:
                for line in f:
                    if line.strip().startswith("CITY_CODE="):
                        code = line.split("=",1)[1].strip()
        except Exception:
            pass
        if code:
            try:
                r = requests.get(f"http://t.weather.sojson.com/api/weather/city/{code}", headers=headers, timeout=10)
                if r.status_code == 200:
                    j = r.json()
                    if j.get("status") == 200 and j.get("data"):
                        data = j["data"]
                        wendu = data.get("wendu", "??")
                        city = j.get("cityInfo", {}).get("city", loc)
                        fc = data.get("forecast", [{}])[0]
                        weather = fc.get("type", "未知")
                        high = fc.get("high", "").replace("高温 ","").replace("℃","")
                        icon = "󰖐"
                        if "晴" in weather: icon = "󰖙"
                        elif "多云" in weather: icon = "󰖐"
                        elif "雨" in weather: icon = "󰖗"
                        elif "雷" in weather: icon = "󰙾"
                        elif "雪" in weather: icon = "󰼶"
                        return {"text": f"{icon} {wendu}°C", "tooltip": f"城市: {city}\n状态: {weather}\n高温: {high}°C\n湿度: {data.get('shidu','')}", "class": "weather"}
            except Exception:
                pass
        # 兜底 wttr.in
        url = f"https://wttr.in/{loc}?format=j1" if loc else "https://wttr.in/?format=j1"
        response = requests.get(url, headers=headers, timeout=15)

        if response.status_code != 200:
            return {"text": "󰖪 ", "tooltip": f"服务器响应错误: {response.status_code}"}

        data = response.json()

        if not data or 'current_condition' not in data:
            return {"text": "󰖪 ", "tooltip": "数据结构异常：wttr.in 可能正在限流"}

        current = data['current_condition'][0]
        temp_c = current.get('temp_C', '??')
        weather_code = current.get('weatherCode', '113')

        desc = "未知"
        if 'lang_zh' in current and current['lang_zh']:
            desc = current['lang_zh'][0]['value']
        elif 'weatherDesc' in current and current['weatherDesc']:
            desc = current['weatherDesc'][0]['value']

        icons = {
            "113": "󰖙", "116": "󰖕", "119": "󰖐", "122": "󰖐",
            "143": "󰖑", "176": "󰖗", "200": "󰙾", "296": "󰖗",
            "302": "󰖖", "338": "󰼶",
        }
        icon = icons.get(weather_code, "󰖐")

        area = "未知地点"
        if 'nearest_area' in data and data['nearest_area']:
            area = data['nearest_area'][0]['areaName'][0]['value']

        return {
            "text": f"{icon} {temp_c}°C",
            "tooltip": f"城市: {area}\n状态: {desc}\n体感: {current.get('FeelsLikeC', '??')}°C\n湿度: {current.get('humidity', '??')}%",
            "class": "weather"
        }
    except Exception as e:
        return {"text": "󰖪 ", "tooltip": f"发生异常: {str(e)}"}

def read_cache():
    try:
        with open(CACHE) as f:
            return f.read().strip()
    except Exception:
        return ""

def spawn_background_fetch():
    """后台拉取天气 → 写缓存 → 通知 waybar 刷新，全程不阻塞主进程"""
    try:
        subprocess.Popen(
            [sys.executable, os.path.realpath(__file__), "--fetch"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            stdin=subprocess.DEVNULL, start_new_session=True,
        )
    except Exception:
        pass

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--fetch":
        # 后台模式：拉取 → 写缓存 → 通知 waybar
        result = fetch_weather()
        os.makedirs(os.path.dirname(CACHE), exist_ok=True)
        with open(CACHE, "w") as f:
            f.write(json.dumps(result))
        subprocess.run(["pkill", "-RTMIN+10", "waybar"], stderr=subprocess.DEVNULL)
        sys.exit(0)

    # 前台模式（waybar exec 调用）：
    if os.path.exists(CACHE) and time.time() - os.path.getmtime(CACHE) < FRESH_SECONDS:
        # 1. 有新鲜缓存 → 立即显示，零等待
        print(read_cache())
    elif read_cache():
        # 2. 有过期缓存 → 先显示旧值，后台刷新
        print(read_cache())
        spawn_background_fetch()
    else:
        # 3. 无缓存（首次启动）→ 占位符 + 后台拉取
        print(json.dumps({"text": "󰖪 ", "tooltip": "正在获取天气..."}))
        spawn_background_fetch()
