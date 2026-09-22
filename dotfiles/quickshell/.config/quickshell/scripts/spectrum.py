#!/usr/bin/env python3
"""声谱源：pw-record 直采 monitor + numpy rfft，全浮点输出。

为什么不用 cava：本机 cava 未编译 pipewire 支持，只能走 pulse，
而 pipewire-pulse 不转发监听流（parecord 验证全 0）；原生 pw-record 有信号。

链路分工（抖动在这里一次性解决，不在 QML 里打补丁）：
- 全局慢基准＋高频静态预加重：低音不再压扁高频，曲线固定不漂移；
  （分段自归一试过：每段恒满格、动态死光，已退回）
- 声卡跟随：连续静音超限即重找 monitor（蓝牙连断/HDMI 拔插后自愈）；
- 绝对门限 FLOOR：环境底噪直接归零，防止无声时自归一吹满格；
- VU 弹道：限速上冲 + 线性 falloff，有限时间精确到站；
  指数趋近永远到不了站、永恒爬行——那是"颤抖"本体，此处不用。
- 全浮点行协议 "0.312;0.045;..."（12 柱），量化只在 QML 落像素时发生一次。

行协议解析见 components/SpectrumState.qml。
"""
import subprocess
import time

import numpy as np

BARS = 12
RATE = 48000
CHUNK = 4096  # ~86ms @48k ≈12Hz：窗长则频稳帧稳，与 50-80ms 取帧时钟同拍，不打架
FMIN, FMAX = 40.0, 16000.0
GAMMA = 0.7  # 弱段上提，0.5 以下全员顶格互搏
AMP = 1.0  # 单一振幅旋钮（QML 侧不再各自加增益）
FLOOR = 5e-5  # 绝对门限：底噪归零，防止无声时自归一吹满格
RISE = 0.23  # 上冲限速/帧（12Hz 下全幅约 0.4s）：跟上鼓点但不瞬移
FALL = 0.06  # 下落固定速度/帧（12Hz 下全幅约 1.4s）：针式表的沉稳感


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


def start_pw(mon):
    if not mon:
        return None
    return subprocess.Popen(
        ["pw-record", "-a", "--format", "f32", "--channels", "1",
         "--rate", str(RATE), "--target", mon, "-"],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)


def main():
    mon = resolve_monitor()
    proc = start_pw(mon)
    freqs = np.fft.rfftfreq(CHUNK, 1.0 / RATE)
    edges = np.logspace(np.log10(FMIN), np.log10(FMAX), BARS + 1)
    idx = np.searchsorted(edges, freqs)
    win = np.hanning(CHUNK)
    buf = b""
    need = CHUNK * 4
    zeros = ";".join(["0"] * BARS)
    refs = 0.0  # 全局慢最大值：分段自归一会让每段恒满格、动态死光，退回全局
    hold = [0.0] * BARS  # VU 弹道输出态
    zero_run = 0  # 连续静音帧：超限即重找声卡（蓝牙/外接切换是常态）
    while True:
        if proc is None or proc.poll() is not None:
            mon = resolve_monitor()
            proc = start_pw(mon)
            buf = b""
            if proc is None:
                print(zeros, flush=True)
                time.sleep(0.5)
                continue
        while len(buf) < need:
            chunk = proc.stdout.read(need - len(buf))
            if not chunk:
                proc = None
                break
            buf += chunk
        if proc is None or len(buf) < need:
            continue
        raw, buf = buf[:need], buf[need:]
        a = np.frombuffer(raw, dtype=np.float32) * win
        mag = np.abs(np.fft.rfft(a))
        vals = []
        for i in range(BARS):
            m = mag[idx == i + 1]
            v = float(np.max(m)) if m.size else 0.0
            vals.append(0.0 if v < FLOOR else v)
        if max(vals) <= 0.0:
            refs *= 0.9
            hold = [max(0.0, h - 0.2) for h in hold]
            print(zeros if max(hold) <= 0.0 else ";".join(f"{v:.3f}" for v in hold), flush=True)
            # 当前这路哑了 8 秒就重找：声卡切换（蓝牙连断/HDMI 拔插）后自愈
            zero_run += 1
            if zero_run > 100:
                zero_run = 0
                new_mon = resolve_monitor()
                if new_mon and new_mon != mon:
                    mon = new_mon
                    try:
                        proc.kill()
                    except Exception:
                        pass
                    proc = None
                    refs = 0.0
                    hold = [0.0] * BARS
            continue
        zero_run = 0
        gv = max(vals)
        refs += (gv - refs) * (0.3 if gv > refs else 0.05)
        base = max(refs, 1e-9)
        for i in range(BARS):
            # 高频段固定预加重（低音压不住高频，静态曲线可预测，不随音乐漂）
            eq = 1.0 + i * 0.06
            norm = vals[i] / base
            target = min(1.5, AMP * eq * norm ** GAMMA)
            h = hold[i]
            hold[i] = min(target, h + RISE) if target > h else max(target, h - FALL)
        print(";".join(f"{v:.3f}" for v in hold), flush=True)


main()
