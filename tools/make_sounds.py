"""Makes HCrafter's sounds from scratch: plain sine tones with soft bell
envelopes. No samples or recordings are used, so the sounds are original to
HCrafter and ship under its license. The first five came with 1.0.0, the
other five with 1.2.0. Each one is made the same way every time.

usage: python3 make_sounds.py <output folder>
"""
import math
import struct
import sys
import wave

RATE = 22050
PEAK = 0.45  # about -7 dB below full scale


def bell(freq, start, length, gain=1.0, decay=5.0, harmonics=((1, 1.0), (2, 0.28), (3, 0.08))):
    """one bell-like note: fast attack, exponential decay, a few harmonics"""
    notes = []
    for mult, amp in harmonics:
        notes.append((freq * mult, amp * gain, start, length, decay * (1 + 0.6 * (mult - 1))))
    return notes


def render(notes, total, vibrato=0.0):
    n = int(total * RATE)
    out = [0.0] * n
    for freq, amp, start, length, decay in notes:
        s0 = int(start * RATE)
        s1 = min(n, int((start + length) * RATE))
        attack = int(0.006 * RATE)
        for i in range(s0, s1):
            t = (i - s0) / RATE
            env = math.exp(-decay * t)
            if i - s0 < attack:
                env *= (i - s0) / attack
            # a gentle fade at the very end of the note
            tail = (s1 - i) / RATE
            if tail < 0.02:
                env *= tail / 0.02
            phase = 2 * math.pi * freq * t
            if vibrato:
                phase += vibrato * math.sin(2 * math.pi * 5.5 * t)
            out[i] += amp * env * math.sin(phase)
    peak = max(1e-9, max(abs(v) for v in out))
    return [v / peak * PEAK for v in out]


def write(path, samples):
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, v)) * 32767)) for v in samples))


def main(folder):
    # ready: two soft chimes, a fifth apart
    ready = bell(880.0, 0.0, 0.5, 1.0, 6.0) + bell(1318.5, 0.11, 0.42, 0.85, 6.5)
    write(folder + '/ready.wav', render(ready, 0.56))

    # level up: a rising C major arpeggio that rings out
    levelup = []
    for i, f in enumerate((523.25, 659.25, 783.99, 1046.5)):
        levelup += bell(f, i * 0.11, 1.0 - i * 0.08, 1.0, 3.2)
    levelup += bell(1318.5, 0.44, 0.7, 0.45, 3.5)
    write(folder + '/levelup.wav', render(levelup, 1.15))

    # hq: a quick high sparkle
    hq = (bell(1567.98, 0.0, 0.35, 0.9, 7.0) + bell(2093.0, 0.07, 0.35, 0.8, 7.5)
          + bell(2637.0, 0.14, 0.4, 0.6, 7.0))
    write(folder + '/hq.wav', render(hq, 0.6))

    # big hq: arpeggio, then a held major chord with a little vibrato
    big = []
    for i, f in enumerate((783.99, 987.77, 1174.66, 1567.98)):
        big += bell(f, i * 0.09, 0.5, 0.9, 5.0)
    for f in (783.99, 987.77, 1174.66, 1567.98):
        big += bell(f, 0.38, 1.2, 0.55, 1.8)
    big += bell(2349.3, 0.5, 0.9, 0.3, 3.0)
    write(folder + '/hq_big.wav', render(big, 1.6, vibrato=0.6))

    # break: two low notes stepping down, soft and short
    brk = (bell(329.63, 0.0, 0.32, 1.0, 7.0, ((1, 1.0), (2, 0.15)))
           + bell(246.94, 0.14, 0.42, 1.0, 6.0, ((1, 1.0), (2, 0.12))))
    write(folder + '/break.wav', render(brk, 0.58))

    # three chimes: quick bells stepping up, for "synths done"
    chimes = (bell(1318.5, 0.0, 0.45, 1.0, 5.5) + bell(1567.98, 0.13, 0.45, 0.95, 5.5)
              + bell(2093.0, 0.26, 0.6, 0.9, 4.5))
    write(folder + '/chimes.wav', render(chimes, 0.9))

    # bell: one warm, slow bell with a slightly uneven overtone
    warm = bell(523.25, 0.0, 1.5, 1.0, 2.2, ((1, 1.0), (2, 0.42), (3, 0.16), (4.2, 0.07)))
    write(folder + '/bell.wav', render(warm, 1.55))

    # ding-dong: two notes stepping down, like a doorbell
    dingdong = (bell(659.25, 0.0, 0.7, 1.0, 3.6, ((1, 1.0), (2, 0.3), (3, 0.1)))
                + bell(523.25, 0.34, 0.9, 1.0, 3.2, ((1, 1.0), (2, 0.3), (3, 0.1))))
    write(folder + '/dingdong.wav', render(dingdong, 1.25))

    # blip: one short high note
    blip = bell(1760.0, 0.0, 0.16, 1.0, 16.0, ((1, 1.0), (2, 0.2)))
    write(folder + '/blip.wav', render(blip, 0.18))

    # alert: two notes back and forth, twice, for "out of a material"
    alert = []
    for i, f in enumerate((880.0, 659.25, 880.0, 659.25)):
        alert += bell(f, i * 0.14, 0.13, 1.0, 9.0, ((1, 1.0), (2, 0.25), (3, 0.1)))
    write(folder + '/alert.wav', render(alert, 0.6))


if __name__ == '__main__':
    main(sys.argv[1])
