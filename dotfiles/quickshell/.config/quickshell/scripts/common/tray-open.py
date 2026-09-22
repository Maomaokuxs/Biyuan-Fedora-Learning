#!/usr/bin/env python3
"""托盘左键通用链（零应用名，不写个例）。

用法：tray-open.py <id> <title> <tip>（托盘项三件套，QML 透传）。
1. 模糊找窗：三件套分词后与窗口 app_id/title 双向子串匹配，
   命中且未聚焦 → 聚焦；已聚焦则跳过（给 toggle 类留 Activate 机会）。
2. 调 Activate：方法缺失会报错（QML 里探不到，这里能）→ 成功即收工。
3. 触发菜单显示项（显示/Show/Open/打开/恢复…）→ 成功即收工。
"""
import json
import re
import subprocess
import sys

from gi.repository import Gio, GLib

DROP_WORDS = {"status", "icon", "icons", "indicator", "notification",
              "item", "items", "tray", "menu", "app", "desktop", "org",
              "com", "net", "io"}

LOG_PATH = "/tmp/tray-open.log"


def log(*parts):
    try:
        with open(LOG_PATH, "a") as f:
            f.write(" ".join(str(p) for p in parts) + "\n")
    except Exception:
        pass
SHOW_LABELS = ["显示", "显示窗口", "打开", "打开面板", "恢复",
               "show window", "open window", "restore"]


def bus():
    return Gio.bus_get_sync(Gio.BusType.SESSION, None)


def tokens(*parts):
    out = []
    for p in parts:
        for w in re.findall(r"[a-z0-9]+", str(p or "").lower()):
            if len(w) >= 3 and w not in DROP_WORDS:
                out.append(w)
    return out


def list_windows():
    try:
        out = subprocess.run(["niri", "msg", "-j", "windows"],
                             capture_output=True, text=True, timeout=5).stdout
        return json.loads(out)
    except Exception:
        return []


def focus_window(toks):
    """模糊命中且未聚焦则聚焦，返回 True；已聚焦/无命中返回 False。"""
    wins = list_windows()
    best = None
    best_key = None
    for w in wins:
        hay = ((str(w.get("app_id") or "") + " " + str(w.get("title") or ""))
               .lower())
        score = 0
        for t in toks:
            if t in hay:
                score = max(score, len(t))
        if score < 3:
            continue
        ts = (w.get("focus_timestamp") or {}).get("secs", 0)
        key = (score, ts)
        if best_key is None or key > best_key:
            best_key = key
            best = w
    if best is None:
        return False
    if best.get("is_focused") is True:
        return False
    try:
        subprocess.run(["niri", "msg", "action", "focus-window",
                        "--id", str(best.get("id"))],
                       timeout=5, check=False)
        return True
    except Exception:
        return False


def find_item(toks):
    """按三件套找托盘项，返回 (svc, path) 或 None。"""
    try:
        b = bus()
        watcher = Gio.DBusProxy.new_sync(b, 0, None,
                                         "org.kde.StatusNotifierWatcher",
                                         "/StatusNotifierWatcher",
                                         "org.kde.StatusNotifierWatcher", None)
        prop = watcher.get_cached_property("RegisteredStatusNotifierItems")
        addrs = prop.unpack() if prop is not None else []
    except Exception:
        return None
    best = None
    best_score = 0
    try:
        b = bus()
        for addr in addrs:
            if "/" in addr:
                svc, path = addr.split("/", 1)
                path = "/" + path
            else:
                svc, path = addr, "/StatusNotifierItem"
            try:
                item = Gio.DBusProxy.new_sync(b, 0, None, svc, path,
                                              "org.kde.StatusNotifierItem", None)
                iid = item.get_cached_property("Id")
                title = item.get_cached_property("Title")
                hay = ((str(iid.unpack() if iid is not None else "")) + " " +
                       (str(title.unpack() if title is not None else ""))).lower()
                score = 0
                for t in toks:
                    if t in hay:
                        score = max(score, len(t))
                if score >= 3 and score > best_score:
                    best_score = score
                    best = (svc, path)
            except Exception:
                continue
    except Exception:
        pass
    return best


def try_activate(svc, path):
    """调 Activate，方法存在即返回 True（缺失/报错返回 False）。"""
    try:
        b = bus()
        proxy = Gio.DBusProxy.new_sync(b, 0, None, svc, path,
                                       "org.kde.StatusNotifierItem", None)
        proxy.call_sync("Activate", GLib.Variant("(ii)", (0, 0)),
                        Gio.DBusCallFlags.NONE, 5000, None)
        return True
    except Exception:
        return False


def walk_layout(node, labels):
    try:
        item_id, props, children = node[0], node[1], node[2]
    except Exception:
        return None
    try:
        label = str(props.get("label", "") or "")
    except Exception:
        label = ""
    ll = label.lower()
    for want in labels:
        if ll == want.lower():
            return item_id
    try:
        for ch in children:
            hit = walk_layout(ch, labels)
            if hit is not None:
                return hit
    except Exception:
        pass
    return None


def menu_show(svc, path):
    try:
        b = bus()
        item = Gio.DBusProxy.new_sync(b, 0, None, svc, path,
                                      "org.kde.StatusNotifierItem", None)
        menup = item.get_cached_property("Menu")
        menupath = str(menup.unpack()) if menup is not None else ""
        if not menupath or menupath == "/":
            return False
        menu = Gio.DBusProxy.new_sync(b, 0, None, svc, menupath,
                                      "com.canonical.dbusmenu", None)
        res = menu.call_sync("GetLayout",
                             GLib.Variant("(iias)", (0, 3, [])),
                             Gio.DBusCallFlags.NONE, 5000, None)
        hit = walk_layout(res.unpack()[1], SHOW_LABELS)
        if hit is None:
            return False
        menu.call_sync("Event",
                       GLib.Variant("(isvu)", (int(hit), "clicked",
                                               GLib.Variant("a{sv}", {}), 0)),
                       Gio.DBusCallFlags.NONE, 5000, None)
        return True
    except Exception:
        return False


def try_secondary(svc, path):
    try:
        b = bus()
        proxy = Gio.DBusProxy.new_sync(b, 0, None, svc, path,
                                       "org.kde.StatusNotifierItem", None)
        proxy.call_sync("SecondaryActivate", GLib.Variant("(ii)", (0, 0)),
                        Gio.DBusCallFlags.NONE, 5000, None)
        return True
    except Exception:
        return False


def main():
    args = (sys.argv[1:] + ["", "", ""])[:3]
    toks = tokens(*args)
    log("CLICK args=", args, "toks=", toks)
    if not toks:
        log("RESULT no-tokens")
        return 1
    if focus_window(toks):
        log("RESULT focused-window")
        return 0
    log("STEP no-window-match")
    found = find_item(toks)
    log("STEP tray-item=", found)
    if found is None:
        log("RESULT item-not-found")
        return 1
    if try_activate(*found):
        log("RESULT activated")
        return 0
    log("STEP activate-failed")
    if menu_show(*found):
        log("RESULT menu-show-triggered")
        return 0
    log("STEP menu-show-failed")
    if try_secondary(*found):
        log("RESULT secondary-ok")
        return 0
    log("RESULT all-failed")
    return 1


sys.exit(main())
