"""Generates the preset alarm ringtones in assets/sounds/ringtones/.

The tones are synthesised (no samples), so they are free to ship.
Needs numpy and ffmpeg:  python tool/make_ringtones.py
Each file is a few seconds long and is looped by the alarm.
"""
import os
import subprocess
import tempfile
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sounds", "ringtones")


def tone(freq, dur, harmonics=(1.0,), attack=0.005, release=0.02):
    t = np.arange(int(SR * dur)) / SR
    y = sum(a * np.sin(2 * np.pi * freq * (i + 1) * t) for i, a in enumerate(harmonics))
    env = np.minimum(1, t / attack) * np.minimum(1, (dur - t) / release)
    return y * env / sum(harmonics)


def bell(freq, dur, partials=((1, 1.0), (2.0, 0.5), (3.0, 0.25)), decay=3.0):
    t = np.arange(int(SR * dur)) / SR
    y = sum(a * np.sin(2 * np.pi * freq * m * t) * np.exp(-decay * m * t) for m, a in partials)
    return y * np.minimum(1, t / 0.003) / sum(a for _, a in partials)


def silence(dur):
    return np.zeros(int(SR * dur))


def classic_beep():
    beep = tone(1000, 0.09, (1, 0.3))
    group = np.concatenate([np.concatenate([beep, silence(0.07)]) for _ in range(4)])
    return np.concatenate([np.concatenate([group, silence(0.45)]) for _ in range(4)])


def digital():
    a, b = tone(880, 0.12, (1, 0.5, 0.25)), tone(1320, 0.12, (1, 0.5, 0.25))
    bar = np.concatenate([a, b, a, b, a, b, silence(0.35)])
    return np.concatenate([bar] * 4)


def gentle_chime():
    notes = [523.25, 659.25, 783.99, 1046.5, 783.99, 659.25]
    y = np.zeros(int(SR * 5.2))
    for i, f in enumerate(notes):
        b = bell(f, 2.2, decay=1.6)
        start = int(SR * 0.75 * i)
        y[start:start + len(b)] += b[: len(y) - start]
    return y


def rising():
    steps = [392, 440, 494, 523, 587, 659, 740, 784]
    parts = []
    for i, f in enumerate(steps):
        parts += [tone(f, 0.32, (1, 0.4, 0.15), attack=0.03, release=0.08) * (0.35 + 0.65 * i / 7), silence(0.08)]
    return np.concatenate(parts + [silence(0.5)])


def siren():
    dur = 6.0
    t = np.arange(int(SR * dur)) / SR
    freq = 800 + 350 * np.sin(2 * np.pi * 0.75 * t)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    y = np.sin(phase) + 0.3 * np.sin(2 * phase)
    return y / 1.3


def bell_tower():
    strike = bell(220, 2.4, ((1, 1.0), (2.0, 0.6), (2.4, 0.5), (3.0, 0.3), (4.2, 0.2)), decay=0.9)
    y = np.zeros(int(SR * 6.0))
    for i in range(3):
        start = int(SR * 1.8 * i)
        y[start:start + len(strike)] += strike[: len(y) - start]
    return y


PRESETS = {
    "classic_beep": classic_beep,
    "digital": digital,
    "gentle_chime": gentle_chime,
    "rising": rising,
    "siren": siren,
    "bell_tower": bell_tower,
}

os.makedirs(OUT, exist_ok=True)
for name, make in PRESETS.items():
    y = make()
    y = 0.89 * y / np.max(np.abs(y))
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        with wave.open(tmp, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes((y * 32767).astype("<i2").tobytes())
    dest = os.path.join(OUT, f"{name}.mp3")
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", tmp.name, "-codec:a", "libmp3lame", "-b:a", "96k", dest],
        check=True,
    )
    os.unlink(tmp.name)
    print(f"{name}.mp3  {len(y) / SR:.1f}s  {os.path.getsize(dest) // 1024} KB")
