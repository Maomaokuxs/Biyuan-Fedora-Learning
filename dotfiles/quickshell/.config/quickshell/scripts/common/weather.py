#!/usr/bin/env python3
import json
import math
import os
import re
import sys
import time
import subprocess
import requests

# 清除代理环境变量：天气定位/请求走真实网络，避免代理出口导致的定位错误
for k in ("http_proxy", "https_proxy", "all_proxy", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY"):
    os.environ.pop(k, None)

CACHE = os.path.expanduser("~/.cache/by-mgr/weather.json")
FRESH_SECONDS = 1800  # 30 分钟内视为新鲜
FAIL_MARK = "/tmp/waybar_weather_fail"
FAIL_COOLDOWN = 600  # 拉取失败后 10 分钟内不再 fork 重试（退避，避免睡醒断网时刷屏）
SIGNAL = "RTMIN+10"   # 后台刷新完成后通知 waybar 重新执行本脚本

CONF = os.path.expanduser("~/.config/by-mgr/weather.conf")
GEO_CACHE = os.path.expanduser("~/.cache/by-mgr/weather-geo.json")  # 地名推导缓存（编码/坐标，按地名串为键）

# 天气图标（Nerd Font 私有区码点，与原脚本逐一对应，勿改）
I_SUN = "\U000F0599"      # 晴
I_PARTLY = "\U000F0595"   # 晴间多云
I_CLOUD = "\U000F0590"    # 多云/阴（默认）
I_FOG = "\U000F0591"      # 雾
I_RAIN = "\U000F0597"     # 雨
I_POUR = "\U000F0596"     # 大雨
I_THUNDER = "\U000F067E"  # 雷
I_SNOW = "\U000F0F36"     # 雪
I_ERR = "\U000F05AA"      # 错误/占位

# Open-Meteo 逐小时补源坐标：不写进代码——conf 显式 LAT=/LON= 优先，
# 缺失时按 LOCATION 地名推导（见 resolved_place()）；都没有则跳过逐小时。

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

def read_city_code():
    """读取 weather.conf 里的 CITY_CODE（sojson 城市编码），无则空串"""
    try:
        with open(CONF) as f:
            for line in f:
                if line.strip().startswith("CITY_CODE="):
                    return line.split("=", 1)[1].strip()
    except Exception:
        pass
    return ""

def read_latlon():
    """读取 weather.conf 里的 LAT=/LON=（Open-Meteo 补源坐标）。
    位置信息只存本地配置文件、绝不写进代码；缺失或非法返回 None。"""
    lat = lon = None
    try:
        with open(CONF) as f:
            for line in f:
                line = line.strip()
                if line.startswith("LAT="):
                    try:
                        lat = float(line.split("=", 1)[1].strip())
                    except Exception:
                        pass
                elif line.startswith("LON="):
                    try:
                        lon = float(line.split("=", 1)[1].strip())
                    except Exception:
                        pass
    except Exception:
        pass
    if lat is None or lon is None:
        return None
    if not (-90 <= lat <= 90 and -180 <= lon <= 180):
        return None
    return (lat, lon)

# ── 地名推导：conf 只写了 LOCATION 时，城市编码与经纬度在运行时按地名推导 ──
# 编码：中国天气网官方全量编码表按中文名检索，候选必须实调 sojson 验真才采用；
# 坐标：Photon（OSM 数据）正向地理编码。推导结果按地名串缓存到 GEO_CACHE，
# 地名不变就直接用缓存、不重复联网推导。conf 显式值永远优先于推导值（见 resolved_place）。

ADMIN_SUFFIXES = ("特别行政区", "自治区", "自治州", "自治县", "自治旗",
                  "地区", "盟", "省", "市", "区", "县", "旗")

def norm_admin(s):
    """行政区划名归一：剥掉省/市/县/区等后缀，供编码表按名匹配"""
    s = (s or "").strip()
    changed = True
    while changed:
        changed = False
        for suf in ADMIN_SUFFIXES:
            if s.endswith(suf) and len(s) > len(suf):
                s = s[:-len(suf)]
                changed = True
                break
    return s

def _get_json(url, params=None, headers=None, timeout=15):
    try:
        r = requests.get(url, params=params,
                         headers=headers or {"User-Agent": "Mozilla/5.0"},
                         timeout=timeout)
        if r.status_code != 200:
            return None
        return r.json()
    except Exception:
        return None

def geocode_place(name):
    """正向地理编码（Photon/OSM，免 key）：在候选中选最佳一条
    {lat, lon, county, city, state}（中文行政名，可能缺字段）。
    选优：带 county 的、本身是县级的优先，其次 place=city/town 的县城点位
    （比行政区质心更贴近县城），其余按源站相关度兜底。失败返回 None。"""
    try:
        r = requests.get("https://photon.komoot.io/api/",
                         params={"q": name, "limit": 8},
                         headers={"User-Agent": "Mozilla/5.0"}, timeout=15)
        if r.status_code != 200:
            return None
        feats = (r.json() or {}).get("features") or []
    except Exception:
        return None
    best = None
    best_score = -1
    for f in feats:
        p = f.get("properties") or {}
        if p.get("countrycode") not in (None, "CN"):
            continue
        coords = (f.get("geometry") or {}).get("coordinates") or []
        if len(coords) != 2:
            continue
        score = 0
        if p.get("county"):
            score += 3
        if p.get("type") == "county":
            score += 3
        if p.get("osm_key") == "place" and p.get("osm_value") in ("city", "town"):
            score += 2
        if p.get("state"):
            score += 1
        if score > best_score:
            best_score = score
            best = {
                "lat": float(coords[1]), "lon": float(coords[0]),
                "county": p.get("county") or (p.get("name") if p.get("type") == "county" else ""),
                "city": p.get("city", ""),
                "state": p.get("state", ""),
            }
    return best

def verify_city_code(code, county):
    """实调 sojson 验真：返回城市名与目标县名归一后一致才算数"""
    j = _get_json(f"http://t.weather.sojson.com/api/weather/city/{code}", timeout=10)
    if not j or j.get("status") != 200:
        return False
    city = (j.get("cityInfo") or {}).get("city", "")
    return bool(city) and norm_admin(city) == norm_admin(county)

def load_code_table():
    """中国天气网官方搜索数据（单文件全量编码表）：省 → 市 → 县 三级嵌套，
    县级节点带 AREAID。源站 CDN 需要带 Referer 才放行。"""
    try:
        r = requests.get("https://j.i8tq.com/weather2020/search/city.js",
                         headers={"User-Agent": "Mozilla/5.0",
                                  "Referer": "https://www.weather.com.cn/"},
                         timeout=20)
        if r.status_code != 200:
            return None
        text = r.text.strip()
        return json.loads(text[text.index("{"):text.rindex("}") + 1])
    except Exception:
        return None

def lookup_city_code(province, county, raw_name=""):
    """在编码表里按名检索县级编码：先限本省（地理编码给的省级名），
    找不到再全表找；同名多个候选时，原始地名串里出现过的市优先；
    每个候选都必须过 sojson 验真才采用，全不过返回空串。"""
    if not county:
        return ""
    table = load_code_table()
    if not table:
        return ""
    target = norm_admin(county)
    prov_norm = norm_admin(province)
    in_prov, out_prov = [], []
    for pname, cities in table.items():
        bucket = in_prov if (prov_norm and norm_admin(pname) == prov_norm) else out_prov
        for cname, counties in (cities or {}).items():
            for dname, info in (counties or {}).items():
                if norm_admin(dname) == target and isinstance(info, dict) and info.get("AREAID"):
                    bucket.append((cname, info["AREAID"]))
    candidates = in_prov + out_prov
    if raw_name:
        candidates.sort(key=lambda c: 0 if norm_admin(c[0]) and norm_admin(c[0]) in raw_name else 1)
    for _cname, code in candidates:
        if verify_city_code(code, county):
            return code
    return ""

def _load_geo_cache():
    try:
        with open(GEO_CACHE) as f:
            d = json.load(f)
            return d if isinstance(d, dict) else {}
    except Exception:
        return {}

def _save_geo_cache(cache):
    try:
        os.makedirs(os.path.dirname(GEO_CACHE), exist_ok=True)
        with open(GEO_CACHE, "w") as f:
            f.write(json.dumps(cache, ensure_ascii=False))
    except Exception:
        pass

def derive_for_name(name):
    """按地名推导 {code, lat, lon}：能推多少算多少，全失败返回 {}。
    命中推导缓存（同名）直接返回、不再联网；新推导出的结果写入缓存。
    缓存里已有的旧条目即使不完整也照用，由调用方按缺项各自兜底。"""
    cache = _load_geo_cache()
    hit = cache.get(name)
    if isinstance(hit, dict) and (hit.get("code") or hit.get("lat") is not None):
        return hit
    entry = {}
    geo = geocode_place(name)
    if geo:
        if geo.get("lat") is not None:
            entry["lat"] = geo["lat"]
            entry["lon"] = geo["lon"]
        code = lookup_city_code(geo.get("state", ""), geo.get("county", ""), raw_name=name)
        if code:
            entry["code"] = code
    if entry:
        cache[name] = entry
        _save_geo_cache(cache)
    return entry

_RESOLVED = None

def resolved_place():
    """本次运行最终采用的 {code, latlon}：conf 显式 CITY_CODE / LAT / LON
    优先，缺项才按 LOCATION 地名推导。推导失败就保持缺项——主源退回
    wttr 按名兜底、逐小时跳过，沿用原有失败纪律，绝不因此报错。"""
    global _RESOLVED
    if _RESOLVED is not None:
        return _RESOLVED
    code = read_city_code()
    latlon = read_latlon()
    if not code or latlon is None:
        name = read_conf()
        if name:
            d = derive_for_name(name)
            if not code and d.get("code"):
                code = d["code"]
            if latlon is None and d.get("lat") is not None:
                latlon = (d["lat"], d["lon"])
    _RESOLVED = {"code": code, "latlon": latlon}
    return _RESOLVED

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

def sojson_icon(wtype):
    """sojson 天气类型 → 图标（与原胶囊口径一致：按关键字包含判定）"""
    icon = I_CLOUD
    if "晴" in wtype: icon = I_SUN
    elif "多云" in wtype: icon = I_CLOUD
    elif "雨" in wtype: icon = I_RAIN
    elif "雷" in wtype: icon = I_THUNDER
    elif "雪" in wtype: icon = I_SNOW
    return icon

def parse_temp(s):
    """'高温 24℃' / '低温 -2℃' → 整数温度，解析失败返回 None"""
    if s is None:
        return None
    m = re.search(r"-?\d+", str(s))
    return int(m.group(0)) if m else None

# 风力等级 → 风速 m/s（蒲福风级中值近似），供体感温度估算
WIND_MS = {0: 0.2, 1: 0.9, 2: 2.5, 3: 4.4, 4: 6.7, 5: 9.4,
           6: 12.3, 7: 15.5, 8: 19.0, 9: 22.6, 10: 26.4, 11: 30.5, 12: 34.8}

def feels_like(temp_c, humidity_pct, fl_str):
    """体感温度（Steadman 表观温度）：温度/湿度/风速估算，返回整数。
    sojson 不直接给体感，面板头部需要，故本地估算；缺湿度按 50% 兜底。"""
    try:
        t = float(temp_c)
    except Exception:
        return None
    rh = humidity_pct if isinstance(humidity_pct, (int, float)) else 50
    lvl = parse_temp(fl_str)
    ws = WIND_MS.get(lvl, 1.5) if lvl is not None else 1.5
    e = rh / 100.0 * 6.105 * math.exp(17.27 * t / (237.7 + t))
    return int(round(t + 0.33 * e - 0.70 * ws - 4.0))

# WMO 天气码（Open-Meteo）→ (中文类型, 图标)，类型口径对齐 sojson
WMO_INFO = {
    0: ("晴", I_SUN), 1: ("晴间多云", I_PARTLY), 2: ("多云", I_CLOUD), 3: ("阴", I_CLOUD),
    45: ("雾", I_FOG), 48: ("雾", I_FOG),
    51: ("小雨", I_RAIN), 53: ("小雨", I_RAIN), 55: ("小雨", I_RAIN),
    56: ("冻雨", I_RAIN), 57: ("冻雨", I_RAIN),
    61: ("小雨", I_RAIN), 63: ("中雨", I_RAIN), 65: ("大雨", I_POUR),
    66: ("冻雨", I_RAIN), 67: ("冻雨", I_RAIN),
    71: ("小雪", I_SNOW), 73: ("中雪", I_SNOW), 75: ("大雪", I_SNOW), 77: ("雪", I_SNOW),
    80: ("阵雨", I_RAIN), 81: ("阵雨", I_RAIN), 82: ("暴雨", I_POUR),
    85: ("阵雪", I_SNOW), 86: ("阵雪", I_SNOW),
    95: ("雷阵雨", I_THUNDER), 96: ("雷阵雨", I_THUNDER), 99: ("雷阵雨", I_THUNDER),
}

def fetch_hourly():
    """Open-Meteo 逐小时（未来 24h）：温度/降雨概率/天气类型。
    只是补源：任何失败都返回空列表，绝不连累主源数据。
    坐标来自 resolved_place()（conf 显式值或地名推导），都没有则跳过。"""
    latlon = resolved_place()["latlon"]
    if latlon is None:
        return []
    try:
        # timezone=auto：时区由坐标自动决定，脚本不写死任何地区
        r = requests.get("https://api.open-meteo.com/v1/forecast", params={
            "latitude": latlon[0], "longitude": latlon[1],
            "hourly": "temperature_2m,precipitation_probability,weather_code",
            "timezone": "auto", "forecast_days": 2,
        }, timeout=10)
        if r.status_code != 200:
            return []
        h = (r.json() or {}).get("hourly") or {}
        times = h.get("time") or []
        temps = h.get("temperature_2m") or []
        pops = h.get("precipitation_probability") or []
        codes = h.get("weather_code") or []
        now_key = time.strftime("%Y-%m-%dT%H:00")
        start = None
        for i, t in enumerate(times):
            if t >= now_key:
                start = i
                break
        if start is None:
            return []
        out = []
        for i in range(start, min(start + 24, len(times))):
            wtype, icon = WMO_INFO.get(codes[i] if i < len(codes) else -1, ("未知", I_CLOUD))
            pop = pops[i] if i < len(pops) else None
            out.append({
                "t": str(times[i])[11:16],
                "temp": temps[i] if i < len(temps) else None,
                "pop": int(pop) if pop is not None else 0,
                "type": wtype,
                "icon": icon,
            })
        return out
    except Exception:
        return []

def sojson_rich(j, data, city):
    """sojson 全量 → 面板富字段（current/today/forecast/notice/ganmao）。
    字段缺失就少给，面板侧按有才显示处理，不在此造假。"""
    rich = {"city": city, "updated": (j.get("cityInfo") or {}).get("updateTime", "")}
    fc_list = data.get("forecast") or []
    fc0 = fc_list[0] if fc_list else {}
    try:
        temp_now = float(data.get("wendu"))
    except Exception:
        temp_now = None
    hum = parse_temp(data.get("shidu"))
    rich["current"] = {
        "temp": temp_now,
        "humidity": hum,
        "type": fc0.get("type", ""),
        "fx": fc0.get("fx", ""),
        "fl": fc0.get("fl", ""),
        "quality": data.get("quality", ""),
        "pm25": data.get("pm25"),
        "pm10": data.get("pm10"),
        "feels": feels_like(temp_now, hum, fc0.get("fl", "")) if temp_now is not None else None,
    }
    rich["today"] = {
        "high": parse_temp(fc0.get("high")),
        "low": parse_temp(fc0.get("low")),
        "sunrise": fc0.get("sunrise", ""),
        "sunset": fc0.get("sunset", ""),
        "aqi": fc0.get("aqi"),
    }
    days = []
    for d in fc_list:
        days.append({
            "ymd": d.get("ymd", ""),
            "date": d.get("date", ""),
            "week": d.get("week", ""),
            "type": d.get("type", ""),
            "icon": sojson_icon(d.get("type", "")),
            "high": parse_temp(d.get("high")),
            "low": parse_temp(d.get("low")),
            "aqi": d.get("aqi"),
            "fx": d.get("fx", ""),
            "fl": d.get("fl", ""),
        })
    rich["forecast"] = days
    rich["notice"] = fc0.get("notice", "")
    rich["ganmao"] = data.get("ganmao", "")
    return rich

def attach_hourly(result):
    """给成功结果补逐小时（补源失败就当没有，不影响主结果落盘）"""
    hourly = fetch_hourly()
    if hourly:
        result["hourly"] = hourly
    return result

def fetch_weather():
    """实时拉取并返回结果 dict"""
    try:
        headers = {'User-Agent': 'Mozilla/5.0'}
        loc = get_location()
        # 国内免 key：优先 sojson（需城市编码）：conf 显式 CITY_CODE= 优先，
        # 缺失时按 LOCATION 地名推导（编码表检索 + 接口验真，见推导区）；
        # 仍无编码则走 wttr.in 兜底（支持任意城市名）
        code = resolved_place()["code"]
        if code:
            try:
                r = requests.get(f"http://t.weather.sojson.com/api/weather/city/{code}", headers=headers, timeout=10)
                if r.status_code == 200:
                    j = r.json()
                    if j.get("status") == 200 and j.get("data"):
                        data = j["data"]
                        wendu = str(int(round(float(data.get("wendu", "0") or 0))))
                        city = j.get("cityInfo", {}).get("city", loc)
                        fc = data.get("forecast", [{}])[0]
                        weather = fc.get("type", "未知")
                        high = fc.get("high", "").replace("高温 ", "").replace("℃", "")
                        icon = sojson_icon(weather)
                        result = {"text": f"{icon} {wendu}°C", "tooltip": f"城市: {city}\n状态: {weather}\n温度: {wendu}°C\n湿度: {data.get('shidu','')}", "class": "weather"}
                        result.update(sojson_rich(j, data, city))
                        return attach_hourly(result)
            except Exception:
                pass
        # 兜底 wttr.in
        url = f"https://wttr.in/{loc}?format=j1" if loc else "https://wttr.in/?format=j1"
        response = requests.get(url, headers=headers, timeout=15)

        if response.status_code != 200:
            return {"text": f"{I_ERR} ", "tooltip": f"服务器响应错误: {response.status_code}"}

        data = response.json()

        if not data or 'current_condition' not in data:
            return {"text": f"{I_ERR} ", "tooltip": "数据结构异常：wttr.in 可能正在限流"}

        current = data['current_condition'][0]
        temp_c = current.get('temp_C', '??')
        weather_code = current.get('weatherCode', '113')

        desc = "未知"
        if 'lang_zh' in current and current['lang_zh']:
            desc = current['lang_zh'][0]['value']
        elif 'weatherDesc' in current and current['weatherDesc']:
            desc = current['weatherDesc'][0]['value']

        icons = {
            "113": I_SUN, "116": I_PARTLY, "119": I_CLOUD, "122": I_CLOUD,
            "143": I_FOG, "176": I_RAIN, "200": I_THUNDER, "296": I_RAIN,
            "302": I_POUR, "338": I_SNOW,
        }
        icon = icons.get(weather_code, I_CLOUD)

        area = "未知地点"
        if 'nearest_area' in data and data['nearest_area']:
            area = data['nearest_area'][0]['areaName'][0]['value']

        return attach_hourly({
            "text": f"{icon} {temp_c}°C",
            "tooltip": f"城市: {area}\n状态: {desc}\n体感: {current.get('FeelsLikeC', '??')}°C\n湿度: {current.get('humidity', '??')}%",
            "class": "weather"
        })
    except Exception as e:
        return {"text": f"{I_ERR} ", "tooltip": f"发生异常: {str(e)}"}

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

def failed_recently():
    """10 分钟内刚失败过 → 不再 fork，由 interval 下一轮再试"""
    try:
        return time.time() - os.path.getmtime(FAIL_MARK) < FAIL_COOLDOWN
    except Exception:
        return False

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--fetch":
        # 后台模式：成功才写缓存；失败不覆盖上次好数据，只记失败时间退避
        result = fetch_weather()
        if result.get("class") == "weather":
            os.makedirs(os.path.dirname(CACHE), exist_ok=True)
            with open(CACHE, "w") as f:
                f.write(json.dumps(result))
            try:
                os.remove(FAIL_MARK)
            except Exception:
                pass
            subprocess.run(["pkill", "-RTMIN+10", "waybar"], stderr=subprocess.DEVNULL)
        else:
            with open(FAIL_MARK, "w") as f:
                f.write(str(int(time.time())))
        sys.exit(0)

    # 前台模式（waybar exec 调用）：
    if os.path.exists(CACHE) and time.time() - os.path.getmtime(CACHE) < FRESH_SECONDS:
        # 1. 有新鲜缓存 → 立即显示，零等待
        print(read_cache())
    elif read_cache():
        # 2. 有过期缓存 → 先显示旧值，后台刷新（失败退避期内不 fork）
        print(read_cache())
        if not failed_recently():
            spawn_background_fetch()
    elif not failed_recently():
        # 3. 无缓存（首次启动）→ 占位符 + 后台拉取
        print(json.dumps({"text": f"{I_ERR} ", "tooltip": "正在获取天气..."}))
        spawn_background_fetch()
    else:
        print(json.dumps({"text": f"{I_ERR} ", "tooltip": "网络未就绪，稍后重试"}))
