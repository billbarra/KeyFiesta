#!/usr/bin/env python3
"""合成 12 条卡通搞笑短音效（44.1kHz mono 16-bit caf），全部自有版权。"""
import math
import os
import struct
import subprocess
import tempfile
import wave

SR = 44100
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Resources", "Sounds")
TWO_PI = 2 * math.pi


def envelope(i, n, attack=0.005, release=0.05):
    t, total = i / SR, n / SR
    a = min(1.0, t / attack) if attack > 0 else 1.0
    r = max(0.0, min(1.0, (total - t) / release)) if release > 0 else 1.0
    return min(a, r)


def sweep(f0, f1, dur, shape=lambda x: x, harmonics=((1, 1.0),), wobble=(0, 0)):
    """正弦扫频：f0→f1，可加谐波与颤音 (rate, depth)。"""
    n = int(SR * dur)
    out, phase = [], 0.0
    rate, depth = wobble
    for i in range(n):
        t = i / n
        f = f0 + (f1 - f0) * shape(t)
        if rate:
            f *= 1 + depth * math.sin(TWO_PI * rate * i / SR)
        phase += TWO_PI * f / SR
        s = sum(amp * math.sin(k * phase) for k, amp in harmonics)
        out.append(s * envelope(i, n))
    return out


def noise(dur, lp=0.0):
    """白噪声，lp∈[0,1) 为一阶低通系数。"""
    import random
    random.seed(7)
    n = int(SR * dur)
    out, prev = [], 0.0
    for i in range(n):
        s = random.uniform(-1, 1)
        prev = lp * prev + (1 - lp) * s
        out.append(prev * envelope(i, n))
    return out


def mul_decay(samples, power=1.5):
    n = len(samples)
    return [s * (1 - i / n) ** power for i, s in enumerate(samples)]


def concat(*parts, gap=0.04):
    silence = [0.0] * int(SR * gap)
    out = []
    for j, p in enumerate(parts):
        out += p
        if j < len(parts) - 1:
            out += silence
    return out


def boing():
    return mul_decay(sweep(380, 130, 0.5, harmonics=((1, 1.0), (2, 0.35)), wobble=(28, 0.22)))


def pop():
    body = sweep(900, 350, 0.07, harmonics=((1, 1.0),))
    click = mul_decay(noise(0.02, lp=0.3), power=3)
    return [a + 0.4 * (click[i] if i < len(click) else 0) for i, a in enumerate(body)]


def slide_up():
    return sweep(350, 1250, 0.42, shape=lambda x: x ** 0.8, harmonics=((1, 1.0), (3, 0.12)), wobble=(6, 0.02))


def slide_down():
    return sweep(1250, 350, 0.42, shape=lambda x: x ** 1.2, harmonics=((1, 1.0), (3, 0.12)), wobble=(6, 0.02))


def quack():
    one = mul_decay(sweep(260, 200, 0.16, harmonics=((1, 1.0), (2, 0.6), (3, 0.4), (5, 0.2)), wobble=(85, 0.35)), 1.0)
    return concat(one, one, gap=0.05)


def honk():
    n = int(SR * 0.32)
    out = []
    for i in range(n):
        s = math.sin(TWO_PI * 220 * i / SR) + 0.8 * math.sin(TWO_PI * 330 * i / SR)
        s += 0.3 * (1 if math.sin(TWO_PI * 220 * i / SR) > 0 else -1)
        out.append(s * envelope(i, n, attack=0.02, release=0.08))
    return out


def toot():
    base = noise(0.36, lp=0.92)
    out = []
    for i, s in enumerate(base):
        flutter = 0.5 + 0.5 * math.sin(TWO_PI * (70 + 25 * math.sin(TWO_PI * 7 * i / SR)) * i / SR)
        out.append(s * flutter)
    return mul_decay(out, 1.2)


def squeak():
    return mul_decay(sweep(1400, 1850, 0.16, shape=lambda x: math.sin(x * math.pi), harmonics=((1, 1.0), (2, 0.2))))


def bubble():
    blips = [mul_decay(sweep(400 + 180 * k, 850 + 180 * k, 0.07), 1.0) for k in range(3)]
    return concat(*blips, gap=0.03)


def ding():
    n = int(SR * 0.5)
    return [(math.sin(TWO_PI * 1318 * i / SR) + 0.4 * math.sin(TWO_PI * 1318 * 2.76 * i / SR))
            * math.exp(-5.5 * i / n) for i in range(n)]


def whee():
    return sweep(500, 1500, 0.45, shape=lambda x: math.sin(x * math.pi * 0.5), harmonics=((1, 1.0), (2, 0.15)), wobble=(9, 0.05))


def drum():
    kick = mul_decay(sweep(150, 48, 0.16, harmonics=((1, 1.0),)), 2.0)
    snare = mul_decay(noise(0.09, lp=0.4), 2.5)
    return concat(kick, snare, gap=0.02)


SOUNDS = {
    "01_boing": boing, "02_pop": pop, "03_slide_up": slide_up, "04_slide_down": slide_down,
    "05_quack": quack, "06_honk": honk, "07_toot": toot, "08_squeak": squeak,
    "09_bubble": bubble, "10_ding": ding, "11_whee": whee, "12_drum": drum,
}


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, fn in SOUNDS.items():
        samples = fn()
        peak = max(1e-9, max(abs(s) for s in samples))
        norm = [s / peak * 0.7 for s in samples]
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
            wav_path = tmp.name
        with wave.open(wav_path, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(b"".join(struct.pack("<h", int(s * 32767)) for s in norm))
        out = os.path.join(OUT_DIR, f"{name}.caf")
        subprocess.run(["afconvert", "-f", "caff", "-d", "LEI16@44100", "-c", "1", wav_path, out], check=True)
        os.unlink(wav_path)
        print(f"OK {out} ({len(samples) / SR:.2f}s)")


if __name__ == "__main__":
    main()
