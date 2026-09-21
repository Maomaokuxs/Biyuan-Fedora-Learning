#!/usr/bin/env python3
"""真频谱桥：pw-record 直采 monitor + numpy rfft，对外行协议与 cava raw 兼容。

为什么不用 cava：本机 cava 未编译 pipewire 支持，只能走 pulse，
而 pipewire-pulse 不转发监听流（parecord 验证全 0）；原生 pw-record 有信号。
行格式 "0;3;7;..."（12 柱，0-7），QML SplitParser 按行吃。
归一按帧内最大值（无状态，不会僵死）；无声/目标丢失时吐全 0 或退出等 QML 重拉。
"""
import subprocess
import sys
import time

import numpy as np

BARS = 12
RATE = 48000
CHUNK = 2048  # ~43ms @48k
FMIN, FMAX = 40.0, 16000.0


def resolve_monitor():
    try:
        out = subprocess.run(
            ["pactl", "list", "sinks", "short"],
            capture_output=True, text=True, timeout=5).stdout
        for line in out.splitlines():
            p = line.split()
            if len(p) >= 3 and p[-1] == "RUNNING":
                name = p[1]
                return name if name.endswith(".monitor") else name + ".monitor"
        out = subprocess.run(
            ["pactl", "get-default-sink"],
            capture_output=True, text=True, timeout=5).stdout.strip()
        if out:
            return out if out.endswith(".monitor") else out + ".monitor"
    except Exception:
        pass
    return None


def main():
    mon = resolve_monitor()
    if not mon:
        while True:
            print(";".join(["0"] * BARS), flush=True)
            time.sleep(0.5)
    freqs = np.fft.rfftfreq(CHUNK, 1.0 / RATE)
    edges = np.logspace(np.log10(FMIN), np.log10(FMAX), BARS + 1)
    idx = np.searchsorted(edges, freqs)
    proc = subprocess.Popen(
        ["pw-record", "-a", "--format", "f32", "--channels", "1",
         "--rate", str(RATE), "--target", mon, "-"],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    win = np.hanning(CHUNK)
    buf = b""
    need = CHUNK * 4
    zeros = ";".join(["0"] * BARS)
    while True:
        while len(buf) < need:
            chunk = proc.stdout.read(need - len(buf))
            if not chunk:
                return
            buf += chunk
        raw, buf = buf[:need], buf[need:]
        a = np.frombuffer(raw, dtype=np.float32) * win
        mag = np.abs(np.fft.rfft(a))
        vals = []
        for i in range(BARS):
            m = mag[idx == i + 1]
            vals.append(float(np.max(m)) if m.size else 0.0)
        peak = max(vals)
        if peak <= 1e-6:
            print(zeros, flush=True)
            continue
        scaled = [min(7, int(round(7 * (vv / peak) ** 0.7))) for vv in vals]
        print(";".join(map(str, scaled)), flush=True)


main()
