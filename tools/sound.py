"""Writes the sound effects (sfx_*.wav) and the music loop (music.ogg) into assets/. 8-bit voices, numpy."""
import subprocess
import wave
from pathlib import Path

import numpy as np
from scipy.signal import butter, lfilter

OUT = Path(__file__).resolve().parent.parent / "assets"
SFX_RATE = 22050
MUSIC_RATE = 32000
rng = np.random.default_rng(7)


def write_wav(path, x, rate):
    x = np.clip(x, -1, 1)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes((x * 32767).astype("<i2").tobytes())


def lowpass(x, hz, rate, order=2):
    b, a = butter(order, hz / (rate / 2), "low")
    return lfilter(b, a, x)


def highpass(x, hz, rate, order=2):
    b, a = butter(order, hz / (rate / 2), "high")
    return lfilter(b, a, x)


def phase(freq, n, rate):
    f = np.broadcast_to(np.asarray(freq, dtype=float), (n,))
    return np.cumsum(f / rate)


def pulse(freq, n, rate, duty=0.5):
    return np.where((phase(freq, n, rate) % 1) < duty, 1.0, -1.0)


def triangle(freq, n, rate, steps=16):
    p = phase(freq, n, rate) % 1
    t = 4 * np.abs(p - 0.5) - 1
    return np.round(t * steps / 2) / (steps / 2)


def sine(freq, n, rate):
    return np.sin(2 * np.pi * phase(freq, n, rate))


def noise(n, rate, hold_hz=8000):
    hold = max(1, int(rate / hold_hz))
    raw = rng.choice([-1.0, 1.0], size=n // hold + 1)
    return np.repeat(raw, hold)[:n]


def env(n, rate, a=0.002, d=0.0, s=1.0, r=0.05):
    t = np.arange(n) / rate
    dur = n / rate
    e = np.ones(n) * s
    if a > 0:
        e = np.where(t < a, t / a, e)
    if d > 0:
        e = np.where((t >= a) & (t < a + d), 1 - (1 - s) * (t - a) / d, e)
    if r > 0:
        e = e * np.clip((dur - t) / r, 0, 1)
    return e


def decay(n, rate, s):
    return np.exp(-np.arange(n) / rate / s)


def sweep(f0, f1, n):
    return np.geomspace(f0, f1, n)


def secs(s, rate=SFX_RATE):
    return int(s * rate)


def norm(x, peak):
    m = np.max(np.abs(x))
    return x if m == 0 else x / m * peak


def notes(midis, each, rate, duty=0.25, peak=0.5):
    parts = []
    for m in midis:
        n = secs(each, rate)
        f = 440 * 2 ** ((m - 69) / 12)
        parts.append(pulse(f, n, rate, duty) * env(n, rate, 0.002, 0.03, 0.6, each * 0.5))
    return norm(np.concatenate(parts), peak)


def sfx():
    R = SFX_RATE
    out = {}
    n = secs(0.07)
    out["hit"] = norm(lowpass(noise(n, R, 6000), 2500, R) * decay(n, R, 0.02) + 0.6 * pulse(sweep(320, 110, n), n, R) * decay(n, R, 0.025), 0.55)
    n = secs(0.16)
    out["kill"] = norm(lowpass(noise(n, R, 4000), 1800, R) * decay(n, R, 0.05) + 0.5 * pulse(sweep(500, 90, n), n, R, 0.25) * decay(n, R, 0.05), 0.5)
    n = secs(0.14)
    out["hurt"] = norm(sine(sweep(170, 55, n), n, R) * decay(n, R, 0.06) + 0.4 * lowpass(noise(n, R, 3000), 1200, R) * decay(n, R, 0.03), 0.7)
    n = secs(0.7)
    out["fall"] = norm(pulse(sweep(420, 60, n), n, R, 0.5) * env(n, R, 0.005, 0, 1, 0.3) + 0.3 * lowpass(noise(n, R, 2000), 800, R) * decay(n, R, 0.3), 0.6)
    n = secs(0.09)
    out["loose"] = norm(highpass(noise(n, R, 11000), 2500, R) * env(n, R, 0.01, 0, 1, 0.07) * 0.5 + pulse(sweep(900, 600, n), n, R, 0.125) * decay(n, R, 0.015), 0.3)
    n = secs(0.22)
    out["cast"] = norm(lowpass(noise(n, R, 9000), np.float64(1400), R) * env(n, R, 0.04, 0, 1, 0.15) + 0.3 * pulse(sweep(140, 260, n), n, R, 0.25) * decay(n, R, 0.08), 0.45)
    n = secs(0.18)
    out["blast"] = norm(lowpass(noise(n, R, 5000), 1500, R) * decay(n, R, 0.07) + 0.5 * sine(sweep(140, 40, n), n, R) * decay(n, R, 0.08), 0.6)
    n = secs(0.1)
    out["spit"] = norm(sine(sweep(260, 520, n), n, R) * env(n, R, 0.005, 0, 1, 0.06) + 0.2 * pulse(sweep(260, 520, n), n, R, 0.5) * decay(n, R, 0.03), 0.35)
    n = secs(0.3)
    clang = sum(pulse(f, n, R, 0.5) * decay(n, R, d) for f, d in ((1180, 0.12), (1730, 0.08), (2410, 0.05)))
    out["block"] = norm(lowpass(clang, 5000, R) + 0.5 * highpass(noise(n, R, 11000), 3000, R) * decay(n, R, 0.01), 0.4)
    out["heal"] = norm(lowpass(notes([76, 83], 0.09, R, 0.5, 1.0), 3000, R), 0.22)
    out["pulse"] = norm(lowpass(triangle(523, secs(0.18), R) * decay(secs(0.18), R, 0.06), 3000, R), 0.18)
    out["level"] = norm(notes([62, 65, 69, 74, 77], 0.07, R, 0.25), 0.45)
    out["recruit"] = norm(notes([62, 69, 74, 69, 78], 0.1, R, 0.5), 0.45)
    n = secs(0.6)
    out["merge"] = norm(pulse(sweep(200, 1600, n), n, R, 0.25) * env(n, R, 0.01, 0, 1, 0.3) * 0.5 + triangle(sweep(100, 800, n), n, R) * env(n, R, 0.01, 0, 1, 0.3), 0.4)
    n = secs(0.9)
    bell = sum(np.roll(pulse(1320, n, R, 0.25) * decay(n, R, 0.12), int(k * 0.13 * R)) * 0.5 ** k for k in range(4))
    out["stop"] = norm(lowpass(pulse(sweep(900, 110, n), n, R, 0.25) * env(n, R, 0.005, 0, 1, 0.5), 2200, R) + 0.5 * lowpass(bell, 4000, R), 0.55)
    n = secs(0.35)
    out["sprout"] = norm(triangle(sweep(90, 260, n), n, R) * env(n, R, 0.01, 0, 1, 0.15) + 0.4 * lowpass(noise(n, R, 3000), 900, R) * decay(n, R, 0.12), 0.45)
    n = secs(0.12)
    out["lash"] = norm(highpass(noise(n, R, 11000), 1800, R) * decay(n, R, 0.025) + 0.4 * pulse(sweep(700, 200, n), n, R, 0.25) * decay(n, R, 0.03), 0.4)
    n = secs(0.3)
    out["lob"] = norm(sine(sweep(300, 700, n), n, R) * env(n, R, 0.01, 0, 1, 0.2) * 0.4 + highpass(noise(n, R, 8000), 1500, R) * env(n, R, 0.05, 0, 1, 0.2) * 0.3, 0.3)
    n = secs(0.35)
    out["boom"] = norm(lowpass(noise(n, R, 4000), 1200, R) * decay(n, R, 0.1) + 0.7 * sine(sweep(120, 35, n), n, R) * decay(n, R, 0.12), 0.65)
    n = secs(0.9)
    out["quake"] = norm(lowpass(noise(n, R, 3000), 700, R) * decay(n, R, 0.3) + sine(sweep(80, 28, n), n, R) * decay(n, R, 0.35) + 0.3 * pulse(sweep(200, 60, n), n, R, 0.5) * decay(n, R, 0.2), 0.85)
    out["strum"] = norm(lowpass(sum(np.roll(triangle(hz, secs(0.9), R) * decay(secs(0.9), R, 0.35), int(i * 0.06 * R)) for i, hz in enumerate((294, 370, 440, 587))), 3500, R), 0.4)
    out["charm"] = norm(notes([81, 86, 88], 0.06, R, 0.125) * 0.6, 0.3)
    n = secs(0.5)
    out["raise"] = norm(lowpass(noise(n, R, 2500), 900, R) * env(n, R, 0.1, 0, 1, 0.3) + 0.6 * pulse(sweep(70, 160, n), n, R, 0.25) * env(n, R, 0.05, 0, 1, 0.3), 0.5)
    n = secs(0.25)
    clack = sum(np.roll(highpass(noise(secs(0.03), R, 9000), 2000, R), 0) * 0 for _ in range(1))
    rattle = np.zeros(n)
    for i in range(5):
        k = int(i * 0.045 * R)
        c = highpass(noise(secs(0.025), R, 9000), 1500, R) * decay(secs(0.025), R, 0.008)
        rattle[k:k + len(c)] += c[: max(0, n - k)]
    out["crumble"] = norm(rattle, 0.4)
    n = secs(0.09)
    out["swing"] = norm(lowpass(highpass(noise(n, R, 10000), 600, R), 3500, R) * env(n, R, 0.015, 0, 1, 0.07), 0.35)
    n = secs(2.2)
    drone = lowpass(pulse(55, n, R, 0.5) + pulse(55 * 1.007, n, R, 0.5) + 0.7 * pulse(41.2, n, R, 0.5), 500, R)
    out["boss"] = norm(drone * env(n, R, 0.05, 0, 1, 1.4) + 0.5 * lowpass(noise(n, R, 2000), 400, R) * decay(n, R, 0.6), 0.75)
    out["defeat"] = norm(lowpass(notes([62, 61, 58, 50], 0.32, R, 0.5), 1800, R), 0.5)
    out["victory"] = norm(notes([62, 66, 69, 74, 74, 78, 81], 0.12, R, 0.25), 0.5)
    out["tick"] = norm(pulse(1000, secs(0.02), R, 0.25) * decay(secs(0.02), R, 0.008), 0.25)
    out["confirm"] = norm(notes([74, 81], 0.04, R, 0.25), 0.3)
    for name, x in out.items():
        write_wav(OUT / f"sfx_{name}.wav", x, R)
    return sorted(out)


BPM = 70
BEAT = 60 / BPM
CHORDS = {
    "Dm": (50, 53, 57), "Bb": (46, 50, 53), "Gm": (43, 46, 50), "A": (45, 49, 52),
    "C": (48, 52, 55), "F": (41, 45, 48), "Eb": (51, 55, 58), "Am": (45, 48, 52),
}
SECTIONS = [
    ("A", ["Dm", "Dm", "Bb", "Bb", "Gm", "Gm", "A", "A"]),
    ("B", ["Dm", "Bb", "Gm", "A", "Dm", "Bb", "C", "A"]),
    ("C", ["Gm", "Eb", "Dm", "A", "Gm", "Eb", "Bb", "A"]),
    ("D", ["Dm", "Bb", "F", "C", "Gm", "Bb", "A", "A"]),
]
LEADS = {
    "B": [[(69, 2), (65, 1), (62, 1)], [(65, 2), (70, 1), (69, 1)], [(67, 3), (70, 1)], [(69, 4)],
          [(74, 2), (72, 1), (69, 1)], [(70, 2), (69, 1), (67, 1)], [(67, 1), (69, 1), (72, 2)], [(73, 3), (69, 1)]],
    "D": [[(74, 3), (72, 1)], [(70, 2), (74, 2)], [(72, 2), (69, 2)], [(67, 3), (64, 1)],
          [(67, 2), (70, 1), (74, 1)], [(77, 2), (74, 2)], [(73, 2), (76, 2)], [(69, 4)]],
}


def hz(m):
    return 440 * 2 ** ((m - 69) / 12)


def music():
    R = MUSIC_RATE
    bars = sum(len(c) for _, c in SECTIONS)
    total = int(bars * 4 * BEAT * R)
    tail = int(4 * R)
    bass = np.zeros(total + tail)
    pad = np.zeros(total + tail)
    arp = np.zeros(total + tail)
    lead = np.zeros(total + tail)
    drums = np.zeros(total + tail)

    def put(buf, at, x):
        i = int(at * R)
        buf[i:i + len(x)] += x[: max(0, len(buf) - i)]

    bar = 0
    for name, chords in SECTIONS:
        for k, c in enumerate(chords):
            t0 = bar * 4 * BEAT
            root, third, fifth = CHORDS[c]
            r = root - 12 if root >= 48 else root
            for beat, length, m in ((0, 1.5, r), (1.5, 0.5, r + 12), (2, 1, r), (3, 1, r + 7)):
                n = int(length * BEAT * R)
                f = hz(m)
                tone = triangle(f, n, R) + 0.8 * sine(f / 2, n, R)
                put(bass, t0 + beat * BEAT, tone * env(n, R, 0.006, 0.15, 0.75, 0.08))
            n = int(4 * BEAT * R)
            chord = sum(pulse(hz(m) * (1 + 0.002 * j), n, R, 0.25) for j, m in enumerate((root, third, fifth)))
            put(pad, t0, chord * env(n, R, 0.35, 0, 1, 0.5))
            if name in ("B", "D", "C"):
                seq = (root + 12, third + 12, fifth + 12, third + 12)
                for s in range(8):
                    n = int(0.5 * BEAT * R)
                    m = seq[s % 4] + (12 if name == "D" and s % 4 == 2 else 0)
                    put(arp, t0 + s * 0.5 * BEAT, pulse(hz(m), n, R, 0.125) * env(n, R, 0.003, 0.08, 0.35, 0.1))
            if name in LEADS:
                at = 0.0
                for m, beats in LEADS[name][k]:
                    n = int(beats * BEAT * R)
                    t = np.arange(n) / R
                    vib = 1 + 0.006 * np.sin(2 * np.pi * 5.2 * t) * np.clip(t / 0.4, 0, 1)
                    put(lead, t0 + at * BEAT, pulse(hz(m - 12) * vib, n, R, 0.5) * env(n, R, 0.02, 0.2, 0.7, 0.12))
                    at += beats
            for beat in (0, 2):
                n = int(0.35 * R)
                put(drums, t0 + beat * BEAT, sine(sweep(110, 42, n), n, R) * decay(n, R, 0.09))
            if name != "A":
                for beat in (1, 3):
                    n = int(0.2 * R)
                    put(drums, t0 + beat * BEAT, 0.25 * lowpass(noise(n, R, 3000), 900, R) * decay(n, R, 0.05))
            bar += 1

    mixed = (
        1.0 * lowpass(bass, 420, R)
        + 0.2 * lowpass(pad, 1100, R)
        + 0.12 * lowpass(arp, 1700, R)
        + 0.34 * lowpass(lead, 1500, R)
        + 0.55 * drums
    )
    mixed = lowpass(mixed, 2600, R)
    mixed[:tail] += mixed[total:total + tail]
    mixed = norm(mixed[:total], 0.7)
    tmp = OUT / "music_tmp.wav"
    write_wav(tmp, mixed, R)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(tmp), "-c:a", "libvorbis", "-q:a", "3", str(OUT / "music.ogg")], check=True)
    tmp.unlink()
    return total / R


print("sfx", sfx())
print(f"music {music():.1f} s")
