"""Synthesizes Wakelatch's alarm sounds (melodic, per McFarlane 2020). Usage: python3 scripts/make-sounds.py <dir>"""
import math, struct, sys, wave

RATE = 44100

def tone(freq, dur, amp):
    n = int(RATE * dur)
    out = []
    for i in range(n):
        t = i / RATE
        env = math.exp(-3.2 * t) * min(1.0, t / 0.008)
        # marimba-like: fundamental plus a soft 4th harmonic
        s = math.sin(2 * math.pi * freq * t) + 0.25 * math.sin(2 * math.pi * freq * 4 * t) * math.exp(-9 * t)
        out.append(amp * env * s)
    return out

def render(pattern, gap, amp, total):
    buf = [0.0] * int(RATE * total)
    t = 0.0
    while t < total - 1.2:
        for f in pattern:
            start = int(t * RATE)
            for i, s in enumerate(tone(f, 1.2, amp)):
                if start + i < len(buf):
                    buf[start + i] += s
            t += gap
        t += gap * 2
    return buf

def write(path, buf):
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32000)) for s in buf))

out = sys.argv[1]
C5, E5, G5, A5, C6, G4, E4 = 523.25, 659.25, 783.99, 880.0, 1046.5, 392.0, 329.63
write(f"{out}/chime.wav", render([C5, E5, G5, C6, G5, E5], 0.22, 0.45, 8.0))
write(f"{out}/nudge.wav", render([E4, G4, C5], 0.38, 0.22, 6.0))
print("ok")
