"""Synthesise three short original instrumentals for the built-in demo tape."""
import numpy as np, wave, sys, os
SR = 44100
rng = np.random.default_rng(7)

def note_hz(n): return 440.0 * 2 ** ((n - 69) / 12)

def env(n, a=0.005, d=0.4, s=0.0, r=0.05, length=None):
    t = np.arange(n) / SR
    e = np.minimum(1, t / a) * (s + (1 - s) * np.exp(-t / d))
    rel = int(r * SR)
    if rel and n > rel: e[-rel:] *= np.linspace(1, 0, rel)
    return e

def keys(freq, dur, bright=1.0):
    n = int(dur * SR); t = np.arange(n) / SR
    mod = np.sin(2 * np.pi * freq * 2 * t) * 1.2 * bright * np.exp(-t / 0.5)
    tone = np.sin(2 * np.pi * freq * t + mod) + 0.25 * np.sin(2 * np.pi * freq * 3 * t) * np.exp(-t / 0.3)
    return tone * env(n, 0.004, 0.9, 0.15, 0.08)

def bass(freq, dur):
    n = int(dur * SR); t = np.arange(n) / SR
    return (np.sin(2 * np.pi * freq * t) + 0.3 * np.sin(4 * np.pi * freq * t)) * env(n, 0.01, 0.35, 0.5, 0.05)

def kick():
    n = int(0.35 * SR); t = np.arange(n) / SR
    f = 50 + 90 * np.exp(-t / 0.04)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.12)

def snare():
    n = int(0.25 * SR); t = np.arange(n) / SR
    return (rng.standard_normal(n) * 0.6 + np.sin(2 * np.pi * 190 * t) * 0.4) * np.exp(-t / 0.07)

def hat():
    n = int(0.06 * SR)
    x = rng.standard_normal(n); x = np.diff(np.concatenate([[0], x]))
    return x * np.exp(-np.arange(n) / SR / 0.015) * 0.5

def place(buf, x, at, gain):
    i = int(at * SR); j = min(len(buf), i + len(x))
    if i < len(buf): buf[i:j] += x[: j - i] * gain

def song(chords, bpm, bars, swing=0.0, root_oct=48, pattern="lofi", lead=None):
    beat = 60 / bpm; total = bars * 4 * beat + 2
    out = np.zeros(int(total * SR))
    for b in range(bars):
        ch = chords[b % len(chords)]; t0 = b * 4 * beat
        for k, n in enumerate(ch):
            place(out, keys(note_hz(n + 12), 4 * beat * 0.95), t0 + k * 0.012, 0.16)
        if pattern == "lofi":
            place(out, keys(note_hz(ch[-1] + 24), beat * 1.5, 0.6), t0 + 2.5 * beat, 0.07)
        place(out, bass(note_hz(ch[0] - 12), beat * 1.8), t0, 0.32)
        place(out, bass(note_hz(ch[0] - 12), beat * 0.9), t0 + 2.5 * beat, 0.25)
        if b >= 1 or pattern != "lofi":
            for q in range(4):
                if q in (0,) or (pattern == "drive" and q == 2): place(out, kick(), t0 + q * beat, 0.55)
                if pattern == "lofi" and q == 2.5: pass
                if q in (1, 3): place(out, snare(), t0 + q * beat, 0.22)
                for h in (0, 0.5):
                    sw = swing * beat if h else 0
                    place(out, hat(), t0 + (q + h) * beat + sw, 0.18)
            if pattern == "lofi": place(out, kick(), t0 + 2.75 * beat, 0.4)
        if lead and b >= 2:
            for (pos, n, d) in lead[b % len(lead)]:
                place(out, keys(note_hz(n + 24), d * beat, 1.4), t0 + pos * beat, 0.09)
    # tape-ish colour: gentle low-pass, hiss, fades
    k = np.ones(6) / 6; out = np.convolve(out, k, mode="same")
    out += rng.standard_normal(len(out)) * 0.0025
    fade = int(1.5 * SR); out[:int(0.2*SR)] *= np.linspace(0, 1, int(0.2*SR)); out[-fade:] *= np.linspace(1, 0, fade)
    out /= np.max(np.abs(out)) * 1.12
    return out

def write(path, x):
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())

outdir = sys.argv[1]
# Dm9 G13 Cmaj9 Am7
tracks = {
 "demo-1-side-street": song([[50,53,57,60,64],[43,53,57,59,64],[48,52,55,59,62],[45,52,55,60,64]], 84, 16, swing=0.12, pattern="lofi",
        lead=[[(0,69,1),(1,72,1),(2,74,2)],[(0,72,1.5),(2,71,2)],[(0,67,1),(1,69,1),(2,71,2)],[(0,69,3)]]),
 "demo-2-night-bus": song([[45,52,55,60],[41,48,55,57],[43,50,55,59],[40,47,55,59]], 96, 16, swing=0.0, pattern="drive",
        lead=[[(0,76,0.5),(0.5,74,0.5),(1,72,1),(2,69,2)],[(0,72,2),(2,74,2)],[(0,71,1),(1,74,1),(2,79,2)],[(0,76,4)]]),
 "demo-3-last-light": song([[48,55,60,64,67],[53,57,60,64],[50,57,60,65],[55,59,62,65]], 72, 14, swing=0.08, pattern="lofi",
        lead=[[(0,76,2),(2,74,2)],[(0,72,4)],[(0,74,2),(2,77,2)],[(0,79,3)]]),
}
for name, x in tracks.items():
    p = os.path.join(outdir, name + ".wav"); write(p, x); print(name, round(len(x) / SR, 1), "s")
