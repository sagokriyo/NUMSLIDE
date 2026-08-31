"""Bakes the win cue: assets/audio/sfx/win.wav.

The clip the app shipped with came across from 2048 with the rest of the sound
palette, and a tic-tac-toe line wants its own voice — shorter, brighter, and
over before the board has finished celebrating.

A four-note rising arpeggio (C6 E6 G6 C7) struck as BELLS: each note is a
fundamental plus three inharmonic partials, and every partial decays faster than
the one below it, which is what separates a bell from an organ. The pair of
delayed, attenuated copies at the end is a cheap room — enough tail that the cue
sounds like it happened somewhere, not enough to smear the arpeggio.

    python tools/win_sting.py

Deterministic: no noise, no randomness, so re-running it reproduces the file
byte for byte.
"""
import math
import struct
import wave
from pathlib import Path

import numpy as np

SR = 44100
OUT = Path(__file__).resolve().parent.parent / "assets" / "audio" / "sfx" / "win.wav"

# (semitone offset from C6, onset in seconds, decay in seconds, gain)
NOTES = [
    (0,  0.000, 0.50, 0.85),   # C6
    (4,  0.085, 0.50, 0.85),   # E6
    (7,  0.170, 0.55, 0.90),   # G6
    (12, 0.290, 1.05, 1.00),   # C7 — the one that rings out
]
# Bell partials: (frequency ratio, amplitude, how much faster it decays)
PARTIALS = [(1.00, 1.00, 1.0), (2.01, 0.42, 1.7), (3.02, 0.20, 2.6), (4.21, 0.09, 3.8)]
C6 = 1046.502
DUR = 1.6
ATTACK = 0.004


def bell(freq, decay):
    """One struck note, `DUR` long, starting at t=0."""
    t = np.arange(int(DUR * SR)) / SR
    out = np.zeros_like(t)
    for ratio, amp, fast in PARTIALS:
        out += amp * np.sin(2.0 * math.pi * freq * ratio * t) * np.exp(-t / (decay / fast))
    # A few ms of attack, or the strike clicks.
    n = int(ATTACK * SR)
    out[:n] *= np.linspace(0.0, 1.0, n)
    return out


def main():
    n = int(DUR * SR)
    left = np.zeros(n)
    right = np.zeros(n)
    for i, (semi, onset, decay, gain) in enumerate(NOTES):
        note = bell(C6 * (2.0 ** (semi / 12.0)), decay) * gain
        start = int(onset * SR)
        seg = note[: n - start]
        # The arpeggio walks left to right across the stereo field as it climbs.
        pan = -0.28 + 0.56 * (i / (len(NOTES) - 1))
        left[start:start + len(seg)] += seg * math.cos((pan + 1.0) * math.pi / 4.0)
        right[start:start + len(seg)] += seg * math.sin((pan + 1.0) * math.pi / 4.0)

    # The room: two delayed, attenuated, channel-swapped copies.
    for delay_ms, level in ((37.0, 0.20), (73.0, 0.11)):
        d = int(delay_ms * 0.001 * SR)
        left[d:] += right[: n - d] * level
        right[d:] += left[: n - d] * level

    stereo = np.stack([left, right], axis=1)
    # Out cleanly: nothing may still be ringing when the buffer ends.
    tail = int(0.08 * SR)
    stereo[-tail:] *= np.linspace(1.0, 0.0, tail)[:, None]
    peak = float(np.max(np.abs(stereo)))
    stereo *= (10.0 ** (-1.5 / 20.0)) / peak          # -1.5 dBFS, no clipping

    pcm = np.clip(np.round(stereo * 32767.0), -32768, 32767).astype("<i2")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    rms = float(np.sqrt(np.mean((pcm / 32768.0) ** 2)))
    print("win.wav: %.2fs  %d frames  peak %.3f dBFS  rms %.1f dBFS  %d bytes"
          % (DUR, len(pcm), 20 * math.log10(np.max(np.abs(pcm)) / 32768.0),
             20 * math.log10(rms), OUT.stat().st_size))


if __name__ == "__main__":
    main()
