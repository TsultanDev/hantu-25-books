"""Procedural horror SFX for HANTU. Pure Python, no dependencies.

Run from the project root:  python tools/generate_audio.py
Outputs 22.05 kHz 16-bit mono WAV files into assets/audio/.
"""

import math
import os
import random
import wave
from array import array

SR = 22050
OUT = os.path.join("assets", "audio")
rng = random.Random(1313)


# ----------------------------------------------------------------------------
# helpers
# ----------------------------------------------------------------------------
def buf(seconds):
    return [0.0] * int(SR * seconds)


def noise(seconds):
    return [rng.uniform(-1.0, 1.0) for _ in range(int(SR * seconds))]


def env_ad(n, attack, decay, power=2.0):
    """Attack/decay envelope over n samples. attack/decay in seconds."""
    a = max(1, int(attack * SR))
    out = [0.0] * n
    for i in range(n):
        if i < a:
            out[i] = (i / a) ** 1.5
        else:
            t = (i - a) / max(1.0, decay * SR)
            out[i] = max(0.0, 1.0 - t) ** power
    return out


def add_tone(b, start, dur, freq, amp, shape="sine", glide=1.0, attack=0.01,
             decay=None, detune=0.0, vibrato=0.0, vibrato_rate=5.0):
    i0 = int(start * SR)
    n = min(len(b) - i0, int(dur * SR))
    if n <= 0:
        return
    if decay is None:
        decay = dur
    e = env_ad(n, attack, decay, 1.6)
    phase = rng.random() * math.tau
    phase2 = rng.random() * math.tau
    for i in range(n):
        t = i / SR
        f = freq * (glide ** (t / max(dur, 1e-5)))
        if vibrato:
            f *= 1.0 + vibrato * math.sin(math.tau * vibrato_rate * t)
        phase += math.tau * f / SR
        if shape == "sine":
            s = math.sin(phase)
        elif shape == "saw":
            s = (phase / math.pi) % 2.0 - 1.0
        elif shape == "square":
            s = 1.0 if math.sin(phase) > 0 else -1.0
        else:
            s = math.sin(phase) + 0.3 * math.sin(phase * 2.01)
        if detune:
            phase2 += math.tau * f * (1.0 + detune) / SR
            s = 0.6 * s + 0.4 * math.sin(phase2)
        b[i0 + i] += s * amp * e[i]


def add_noise(b, start, dur, amp, attack=0.005, decay=None, power=1.5,
              lowpass=0.0, highpass=0.0, bandpass=None, q=1.0):
    i0 = int(start * SR)
    n = min(len(b) - i0, int(dur * SR))
    if n <= 0:
        return
    if decay is None:
        decay = dur
    e = env_ad(n, attack, decay, power)
    lp = 0.0
    hp_state = 0.0
    prev = 0.0
    low = 0.0
    band = 0.0
    if bandpass:
        f = 2.0 * math.sin(math.pi * bandpass / SR)
        damp = 1.0 / max(0.5, q)
    for i in range(n):
        x = rng.uniform(-1.0, 1.0)
        if lowpass:
            lp += (x - lp) * lowpass
            x = lp
        if highpass:
            hp_state = hp_state * 0.98 + x - prev
            prev = x
            x = x - prev + hp_state * highpass
        if bandpass:
            low += f * band
            high = x - low - damp * band
            band += f * high
            x = band
        b[i0 + i] += x * amp * e[i]


def reverb(b, amount=0.3, room=0.7):
    """Cheap multi-tap echo, in place."""
    taps = [0.037, 0.071, 0.113, 0.171, 0.239, 0.311]
    for tap in taps:
        d = int(tap * SR)
        g = amount * (room ** (tap * 8))
        for i in range(d, len(b)):
            b[i] += b[i - d] * g
    return b


def lowpass(b, amount):
    v = 0.0
    for i in range(len(b)):
        v += (b[i] - v) * amount
        b[i] = v
    return b


def normalize(b, peak=0.9):
    p = max(1e-9, max(abs(x) for x in b))
    k = peak / p
    for i in range(len(b)):
        b[i] = math.tanh(b[i] * k * 1.15) * 0.92


def loopify(b, fade=0.6):
    """Crossfade the tail into the head and drop the tail, for a clean loop."""
    n = min(int(fade * SR), len(b) // 3)
    if n <= 0:
        return b
    tail = b[-n:]
    out = b[:-n]
    for i in range(n):
        w = i / n
        out[i] = out[i] * w + tail[i] * (1.0 - w)
    return out


def save(name, b, loop=False):
    if loop:
        b = loopify(b, 0.7)
    normalize(b, 0.82 if loop else 0.92)
    data = array("h", (int(max(-1.0, min(1.0, x)) * 32767) for x in b))
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print(f"{path:36s} {len(data) / SR:5.2f}s")


# ----------------------------------------------------------------------------
# ambience - long, cold, breathing room tone
# ----------------------------------------------------------------------------
def make_ambience():
    b = buf(17.0)
    # sub drone, slowly beating
    add_tone(b, 0, 17, 36.0, 0.20, "sine", attack=2.0, decay=17)
    add_tone(b, 0, 17, 54.5, 0.075, "sine", attack=3.0, decay=17, vibrato=0.004, vibrato_rate=0.11)
    add_tone(b, 0, 17, 73.0, 0.035, "sine", attack=4.0, decay=17, vibrato=0.006, vibrato_rate=0.07)
    # distant windy air
    wind = noise(17.0)
    v = 0.0
    for i in range(len(wind)):
        v += (wind[i] - v) * 0.012
        wind[i] = v
    for i, s in enumerate(wind):
        t = i / SR
        wind[i] = s * (0.5 + 0.5 * math.sin(math.tau * 0.077 * t + 1.0)) * 0.55
    for i in range(len(b)):
        b[i] += wind[i]
    # faint high whine
    add_tone(b, 1.0, 15.0, 2140.0, 0.012, "sine", attack=2.0, decay=15,
             vibrato=0.006, vibrato_rate=0.19)
    # distant settling creaks
    for start, f0, amp in ((2.8, 210, 0.05), (7.6, 165, 0.04), (12.2, 245, 0.045)):
        add_tone(b, start, 1.2, f0, amp, "saw", glide=0.55, attack=0.08,
                 decay=1.2, vibrato=0.03, vibrato_rate=2.0)
    # a breath of air sliding over the floor
    add_noise(b, 9.0, 4.0, 0.035, attack=2.0, decay=4.0, lowpass=0.02)
    reverb(b, 0.35, 0.82)
    save("ambience", b, loop=True)


# ----------------------------------------------------------------------------
# heartbeat - looped two-beat pulse
# ----------------------------------------------------------------------------
def make_heartbeat():
    b = buf(1.25)
    for start, amp in ((0.03, 0.85), (0.33, 0.62)):
        add_tone(b, start, 0.26, 58.0, amp, "sine", glide=0.52,
                 attack=0.004, decay=0.26)
        add_noise(b, start, 0.055, amp * 0.35, attack=0.001, decay=0.05,
                  lowpass=0.12)
    # quiet room tone so the loop is not dead silent
    add_noise(b, 0, 1.25, 0.008, attack=0.2, decay=1.25, lowpass=0.008)
    save("heartbeat", b, loop=True)


# ----------------------------------------------------------------------------
# whisper - breathy, unintelligible voices
# ----------------------------------------------------------------------------
def make_whisper():
    b = buf(9.0)
    syllables = [(0.4, 0.5), (1.2, 0.3), (1.7, 0.6), (3.0, 0.35),
                 (3.7, 0.5), (4.4, 0.25), (5.6, 0.7), (6.5, 0.4),
                 (7.3, 0.55), (8.2, 0.35)]
    for start, dur in syllables:
        fc = rng.uniform(950, 2400)
        add_noise(b, start, dur, rng.uniform(0.25, 0.5), attack=0.09,
                  decay=dur, bandpass=fc, q=rng.uniform(1.8, 4.0))
        # a little voiced tone under the breath
        add_tone(b, start, dur, rng.uniform(120, 210), 0.045, "saw",
                 attack=0.06, decay=dur, vibrato=0.01, vibrato_rate=3.7)
    add_noise(b, 0, 9.0, 0.03, attack=1.0, decay=9.0, bandpass=600, q=0.7)
    reverb(b, 0.45, 0.78)
    save("whisper", b, loop=True)


# ----------------------------------------------------------------------------
# chase - dissonant pulsing strings and drums
# ----------------------------------------------------------------------------
def make_chase():
    b = buf(9.0)
    # driving low pulse
    for i in range(18):
        t = i * 0.5
        add_tone(b, t, 0.35, 48.0, 0.5, "sine", glide=0.75,
                 attack=0.004, decay=0.32)
        add_noise(b, t, 0.09, 0.12, attack=0.001, decay=0.09, lowpass=0.18)
    # dissonant cluster, swelling
    for freq, amp in ((98.0, 0.13), (103.8, 0.12), (146.8, 0.11),
                      (155.6, 0.10), (207.7, 0.05)):
        add_tone(b, 0, 9, freq, amp, "saw", attack=2.5, decay=9,
                 vibrato=0.008, vibrato_rate=5.5)
    # screeching high strings entering later
    add_tone(b, 3.0, 6.0, 1174.7, 0.035, "saw", glide=1.05, attack=1.5,
             decay=6, vibrato=0.02, vibrato_rate=7)
    add_tone(b, 4.2, 4.8, 1244.5, 0.028, "saw", glide=1.02, attack=1.0,
             decay=4.8, vibrato=0.018, vibrato_rate=6.2)
    # skin-crawling breath
    add_noise(b, 0, 9, 0.05, attack=1.5, decay=9, bandpass=1800, q=1.1)
    reverb(b, 0.28, 0.75)
    save("chase", b, loop=True)


# ----------------------------------------------------------------------------
# stinger - the moment it notices you
# ----------------------------------------------------------------------------
def make_stinger():
    b = buf(2.6)
    add_noise(b, 0, 0.5, 0.6, attack=0.001, decay=0.45, highpass=0.6)
    for freq, amp in ((880, 0.18), (932, 0.16), (1245, 0.14), (1865, 0.09)):
        add_tone(b, 0, 1.4, freq, amp, "saw", glide=0.82,
                 attack=0.002, decay=1.4, detune=0.012)
    add_tone(b, 0.02, 2.4, 70, 0.55, "sine", glide=0.4,
             attack=0.002, decay=2.4)
    add_noise(b, 0.0, 2.2, 0.2, attack=0.01, decay=2.2, lowpass=0.05)
    reverb(b, 0.5, 0.8)
    save("stinger", b)


# ----------------------------------------------------------------------------
# scream / jumpscare
# ----------------------------------------------------------------------------
def make_scream(name="scream", chaos=0.0, length=2.4):
    b = buf(length)
    # distorted gliding voices
    for f0, amp, det in ((330, 0.25, 0.017), (495, 0.18, -0.021),
                         (660, 0.11, 0.013)):
        add_tone(b, 0.0, length, f0, amp, "saw", glide=0.28,
                 attack=0.01, decay=length, detune=det,
                 vibrato=0.055, vibrato_rate=11.0)
    # shrieking filtered noise
    add_noise(b, 0, length, 0.5, attack=0.005, decay=length,
              bandpass=2100, q=2.4)
    add_noise(b, 0.05, length * 0.8, 0.3, attack=0.01, decay=length * 0.8,
              highpass=0.7)
    # sub hit
    add_tone(b, 0, 1.3, 55, 0.7, "sine", glide=0.4, attack=0.002, decay=1.3)
    if chaos > 0:
        for _ in range(int(8 * chaos)):
            add_noise(b, rng.uniform(0, length * 0.7), rng.uniform(0.08, 0.35),
                      rng.uniform(0.15, 0.4), attack=0.001,
                      decay=0.3, bandpass=rng.uniform(500, 4000),
                      q=rng.uniform(1.5, 5.0))
        for _ in range(4):
            add_tone(b, rng.uniform(0, 1.4), rng.uniform(0.2, 0.8),
                     rng.uniform(400, 1500), 0.15, "square",
                     glide=0.8, attack=0.001, decay=0.5)
    reverb(b, 0.55, 0.85)
    save(name, b)


# ----------------------------------------------------------------------------
# pickups / doors / ui
# ----------------------------------------------------------------------------
def make_book():
    b = buf(1.15)
    # paper rustle
    add_noise(b, 0.0, 0.32, 0.42, attack=0.005, decay=0.3,
              bandpass=3200, q=1.2)
    add_noise(b, 0.04, 0.25, 0.22, attack=0.005, decay=0.25,
              bandpass=1600, q=1.7)
    # small warm bell
    add_tone(b, 0.14, 0.9, 784, 0.20, "sine", attack=0.005, decay=0.9)
    add_tone(b, 0.14, 0.8, 1174, 0.12, "sine", attack=0.005, decay=0.8)
    add_tone(b, 0.15, 0.7, 1568, 0.06, "sine", attack=0.005, decay=0.7)
    reverb(b, 0.25, 0.7)
    save("book", b)


def make_step():
    b = buf(0.24)
    add_noise(b, 0.0, 0.11, 0.55, attack=0.001, decay=0.10, lowpass=0.16)
    add_tone(b, 0.0, 0.14, 85, 0.38, "sine", glide=0.6, attack=0.001, decay=0.14)
    save("step", b)


def make_locked():
    b = buf(1.1)
    add_tone(b, 0.0, 0.35, 72, 0.7, "sine", glide=0.45, attack=0.001, decay=0.32)
    add_noise(b, 0.0, 0.22, 0.4, attack=0.001, decay=0.2, lowpass=0.2)
    # metal rattle
    for t in (0.12, 0.19, 0.27, 0.41):
        add_noise(b, t, 0.09, 0.28, attack=0.001, decay=0.09,
                  bandpass=rng.uniform(1200, 2600), q=3.0)
    add_tone(b, 0.1, 0.7, 190, 0.08, "square", glide=0.9, attack=0.005,
             decay=0.7, vibrato=0.02, vibrato_rate=9)
    reverb(b, 0.25, 0.7)
    save("locked", b)


def make_unlock():
    b = buf(2.2)
    # long rusted creak
    add_tone(b, 0.0, 1.7, 160, 0.18, "saw", glide=0.45, attack=0.2,
             decay=1.7, vibrato=0.05, vibrato_rate=1.4)
    add_noise(b, 0.0, 1.7, 0.16, attack=0.1, decay=1.6,
              bandpass=1200, q=2.7)
    # heavy clunk
    add_tone(b, 1.3, 0.6, 80, 0.5, "sine", glide=0.6, attack=0.001, decay=0.6)
    # eerie welcome chime
    for f in (523, 659, 784):
        add_tone(b, 1.35, 0.8, f, 0.08, "sine", attack=0.01, decay=0.8)
    reverb(b, 0.4, 0.8)
    save("unlock", b)


def make_win():
    b = buf(5.0)
    # low warm drone
    add_tone(b, 0, 5, 65.4, 0.18, "sine", attack=1.0, decay=5)
    add_tone(b, 0, 5, 98.0, 0.10, "sine", attack=1.5, decay=5)
    # distant choir-ish resolution
    for i, f in enumerate((261.6, 329.6, 392.0, 523.3)):
        add_tone(b, 0.5 + i * 0.12, 4.2, f, 0.07, "sine",
                 attack=1.2, decay=4.2, vibrato=0.006, vibrato_rate=0.4)
    # fragile bell
    add_tone(b, 1.2, 3.2, 1046.5, 0.06, "sine", attack=0.02, decay=3.2)
    add_tone(b, 1.2, 3.0, 1568.0, 0.03, "sine", attack=0.02, decay=3.0)
    reverb(b, 0.5, 0.85)
    save("win", b)


def make_click():
    b = buf(0.12)
    add_noise(b, 0, 0.05, 0.25, attack=0.001, decay=0.05, bandpass=2200, q=2)
    add_tone(b, 0, 0.07, 880, 0.1, "sine", attack=0.001, decay=0.07)
    save("ui_click", b)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    make_ambience()
    make_heartbeat()
    make_whisper()
    make_chase()
    make_stinger()
    make_scream("scream", chaos=0.0, length=2.2)
    make_scream("jumpscare", chaos=1.0, length=2.8)
    make_book()
    make_step()
    make_locked()
    make_unlock()
    make_win()
    make_click()
