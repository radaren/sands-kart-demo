"""Procedural placeholder sound effects (numpy only) -> assets/audio/sfx/*.wav.
Short, mono, 22.05 kHz, 16-bit. Re-run to regenerate; replace with real SFX later."""
import os, wave
import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "sfx")
rng = np.random.default_rng(7)


def t(d):
    return np.arange(int(SR * d)) / SR


def env(n, a=0.005, r=0.1, d=None):
    x = np.ones(n)
    na = max(1, int(a * SR)); nr = max(1, int(r * SR))
    x[:na] = np.linspace(0, 1, na)
    x[-nr:] *= np.linspace(1, 0, nr) ** 2
    return x


def noise(n):
    return rng.uniform(-1, 1, n)


def lowpass(x, k):
    # one-pole low pass, k in (0,1): smaller = darker
    y = np.empty_like(x); acc = 0.0
    for i, v in enumerate(x):
        acc += k * (v - acc); y[i] = acc
    return y


def sweep(f0, f1, d, shape="sin"):
    tt = t(d); f = np.geomspace(f0, f1, len(tt)); ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) if shape == "sin" else np.sign(np.sin(ph)) * 0.6


def save(name, x, gain=0.8):
    x = np.asarray(x, dtype=np.float64)
    x = x / (np.max(np.abs(x)) + 1e-9) * gain
    data = (np.clip(x, -1, 1) * 32767).astype("<i2").tobytes()
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(data)


def main():
    os.makedirs(OUT, exist_ok=True)
    d = 0.12; save("beep", np.sin(2 * np.pi * 880 * t(d)) * env(len(t(d)), 0.003, 0.05), 0.6)
    d = 0.45; save("go", (np.sin(2 * np.pi * 1320 * t(d)) + 0.4 * np.sin(2 * np.pi * 1980 * t(d))) * env(len(t(d)), 0.003, 0.25), 0.7)
    d = 0.6; n = len(t(d))
    save("boost", lowpass(noise(n), 0.25) * env(n, 0.02, 0.4) * 0.8 + 0.5 * sweep(180, 620, d) * env(n, 0.01, 0.35))
    d = 0.35; n = len(t(d))
    save("mini", lowpass(noise(n), 0.35) * env(n, 0.01, 0.25) + 0.4 * sweep(300, 900, d) * env(n, 0.01, 0.2), 0.7)
    d = 0.25; n = len(t(d))
    save("wall", (lowpass(noise(n), 0.08) * 1.5 + 0.8 * np.sin(2 * np.pi * 70 * t(d))) * env(n, 0.002, 0.2))
    d = 0.3; n = len(t(d))
    save("pickup", (np.sin(2 * np.pi * 1046 * t(d)) * (t(d) < 0.1) + np.sin(2 * np.pi * 1568 * t(d)) * (t(d) >= 0.1)) * env(n, 0.003, 0.15), 0.55)
    d = 0.22; n = len(t(d))
    save("use", sweep(500, 1500, d) * env(n, 0.003, 0.12) + 0.3 * lowpass(noise(n), 0.5) * env(n, 0.002, 0.1), 0.6)
    d = 0.9; n = len(t(d))
    save("explode", lowpass(noise(n), 0.06) * env(n, 0.002, 0.8) * 1.4 + 0.6 * sweep(120, 40, d) * env(n, 0.002, 0.7), 0.9)
    d = 0.55; n = len(t(d))
    save("hit", lowpass(noise(n), 0.15) * env(n, 0.002, 0.4) + 0.5 * sweep(600, 120, d) * env(n, 0.005, 0.4), 0.8)
    d = 0.5; n = len(t(d))
    zap = noise(n) * (np.sin(2 * np.pi * 37 * t(d)) > 0) * env(n, 0.002, 0.3)
    save("zap", zap + 0.4 * sweep(2000, 300, d, "sq") * env(n, 0.002, 0.3), 0.75)
    d = 0.35; n = len(t(d))
    save("shield", (np.sin(2 * np.pi * 1200 * t(d)) + 0.6 * np.sin(2 * np.pi * 1810 * t(d))) * np.exp(-t(d) * 9), 0.6)
    d = 0.4; n = len(t(d))
    save("slip", sweep(900, 200, d) * env(n, 0.005, 0.2) * (0.6 + 0.4 * np.sin(2 * np.pi * 18 * t(d))), 0.6)
    d = 0.18; n = len(t(d))
    save("warn", np.sign(np.sin(2 * np.pi * 1500 * t(d))) * 0.5 * env(n, 0.002, 0.03), 0.45)
    notes = [523, 659, 784, 1046]; parts = []
    for i, f in enumerate(notes):
        dd = 0.16 if i < 3 else 0.6
        tt = t(dd); parts.append((np.sin(2 * np.pi * f * tt) + 0.3 * np.sin(4 * np.pi * f * tt)) * env(len(tt), 0.005, dd * 0.6))
    save("finish", np.concatenate(parts), 0.7)
    d = 0.25; n = len(t(d))
    save("ding", (np.sin(2 * np.pi * 1760 * t(d)) + 0.5 * np.sin(2 * np.pi * 2640 * t(d))) * np.exp(-t(d) * 14), 0.6)
    d = 0.3; n = len(t(d))
    save("land", (lowpass(noise(n), 0.05) * 1.2 + 0.7 * np.sin(2 * np.pi * 55 * t(d))) * env(n, 0.002, 0.25), 0.7)


if __name__ == "__main__":
    main()
