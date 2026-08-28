#!/usr/bin/env python3
"""Waybar 歌词模块：显示当前播放歌曲的当前句歌词（酷狗歌词 API）"""
import json, base64, re, subprocess, sys, time, os, urllib.request, urllib.parse

CACHE = "/tmp/waybar_lyric.json"

def playerctl(args):
    try:
        r = subprocess.run(["playerctl", *args], capture_output=True, text=True, timeout=3)
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        return ""

def http_json(url, headers=None):
    req = urllib.request.Request(url, headers=headers or {
        "User-Agent": "KuGou2012-9020-ExpandSearchManager",
        "KG-RC": "1",
        "KG-THash": "expand_search_manager.cpp:852736169:451",
    })
    try:
        with urllib.request.urlopen(req, timeout=6) as r:
            return json.loads(r.read().decode())
    except Exception:
        return None

def get_hash(title, artist, seconds):
    # 歌曲搜索拿 FileHash
    kw = f"{title} {artist}".strip()
    url = "https://songsearch.kugou.com/song_search_v2?" + urllib.parse.urlencode(
        {"keyword": kw, "page": 1, "pagesize": 1, "platform": "WebFilter"})
    d = http_json(url)
    if not d or not d.get("data", {}).get("lists"):
        return None
    return d["data"]["lists"][0].get("FileHash")

def get_lrc(hash_, title, seconds):
    url = "http://lyrics.kugou.com/search?" + urllib.parse.urlencode(
        {"ver": 1, "man": "yes", "client": "pc", "lrctxt": 1,
         "keyword": title, "hash": hash_, "timelength": seconds})
    d = http_json(url)
    if not d or not d.get("candidates"):
        return None
    c = d["candidates"][0]
    dl = "http://lyrics.kugou.com/download?" + urllib.parse.urlencode(
        {"ver": 1, "client": "pc", "fmt": "lrc", "charset": "utf8",
         "id": c["id"], "accesskey": c["accesskey"]})
    d2 = http_json(dl)
    if not d2 or not d2.get("content"):
        return None
    return base64.b64decode(d2["content"]).decode("utf-8", errors="ignore")

TS_RE = re.compile(r"\[(\d+):(\d+(?:\.\d+)?)\]")
def parse_lrc(lrc):
    lines = []
    for line in lrc.splitlines():
        ts = TS_RE.findall(line)
        if not ts: continue
        text = re.sub(r"\[[^\]]*\]", "", line).strip()
        for m, s in ts:
            lines.append((int(m) * 60 + float(s), text))
    return sorted(lines)

def current_line(parsed, pos):
    cur = ""
    for t, text in parsed:
        if t <= pos:
            cur = text
        else:
            break
    return cur

def main():
    if os.path.exists("/tmp/lyric_off"):
        print(json.dumps({"text": "", "class": "hidden", "tooltip": "歌词已关闭（cava 右键开启）"}))
        return
    title = playerctl(["metadata", "xesam:title"])
    artist = playerctl(["metadata", "xesam:artist"])
    length = playerctl(["metadata", "mpris:length"])
    status = playerctl(["status"])
    pos_raw = playerctl(["position"])

    if not title or status != "Playing":
        print(json.dumps({"text": "♪", "class": "idle", "tooltip": "未在播放"}))
        return

    try:
        seconds = int(length) // 1000000 if length else 0
        pos = float(pos_raw) if pos_raw else 0.0
    except Exception:
        seconds, pos = 0, 0.0

    # 缓存 hash（按曲目）
    cache_key = f"{title}|{artist}"
    cached = {}
    if os.path.exists(CACHE):
        try:
            cached = json.load(open(CACHE))
        except Exception:
            cached = {}
    if cached.get("key") != cache_key:
        h = get_hash(title, artist, seconds)
        if not h:
            print(json.dumps({"text": title[:20], "class": "no-lyric", "tooltip": "未找到歌词"}))
            return
        lrc = get_lrc(h, title, seconds)
        if not lrc:
            print(json.dumps({"text": title[:20], "class": "no-lyric", "tooltip": "未找到歌词"}))
            return
        parsed = parse_lrc(lrc)
        cached = {"key": cache_key, "lrc": parsed}
        try:
            json.dump(cached, open(CACHE, "w"))
        except Exception:
            pass
    else:
        parsed = cached.get("lrc", [])

    line = current_line(parsed, pos)
    disp = line if line else title[:24]
    print(json.dumps({
        "text": disp[:26],
        "class": "playing" if line else "instrumental",
        "tooltip": f"{title} - {artist}\n{disp}",
    }))

if __name__ == "__main__":
    main()
