"""Writes Orbit's short completion sounds as WAV files for iOS (ios/App/Sounds).

The notes match OrbitSounds in windows/ui/rewards-ui.js (Windows synthesises them live):
each note is (frequency Hz, start s, length s, volume[, end frequency Hz]), a sine with a 12 ms
attack and an exponential fade. With an end frequency the pitch falls to it over the first 60% of
the note, after a 4 ms attack: a soft pop for a check-off rather than a beep.
Run: python3 scripts/make_sounds.py
"""
import math, struct, wave
from pathlib import Path

SOUNDS = {
    "orbit-tick": [(620, 0, 0.11, 0.07, 340), (1240, 0, 0.045, 0.012, 700)],
    "orbit-day": [(523.25, 0, 0.5, 0.07), (659.25, 0.09, 0.5, 0.07), (783.99, 0.18, 0.6, 0.07), (1046.5, 0.3, 0.9, 0.06)],
    "orbit-badge": [(880, 0, 0.35, 0.06), (1318.5, 0.1, 0.6, 0.06)],
}
RATE = 44100
# Phones play quieter than a desktop's Web Audio graph; scale up while keeping headroom.
GAIN = 6.0

def render(notes):
    length = max(note[1] + note[2] for note in notes) + 0.05
    samples = [0.0] * int(length * RATE)
    for freq, at, dur, vol, *glide in notes:
        start = int(at * RATE)
        attack = 0.004 if glide else 0.012
        phase = 0.0
        for i in range(int(dur * RATE)):
            t = i / RATE
            # A short rise, then an exponential fade to near silence by the note's end.
            env = t / attack if t < attack else (0.0001 / vol) ** ((t - attack) / (dur - attack))
            if glide:
                # Pitch falls exponentially to the end frequency over the first 60% of the note.
                f = freq * (glide[0] / freq) ** min(1, t / (dur * 0.6))
                phase += 2 * math.pi * f / RATE
                samples[start + i] += vol * GAIN * env * math.sin(phase)
            else:
                samples[start + i] += vol * GAIN * env * math.sin(2 * math.pi * freq * t)
    return samples

out = Path(__file__).resolve().parents[1] / "ios/App/Sounds"
out.mkdir(parents=True, exist_ok=True)
for name, notes in SOUNDS.items():
    with wave.open(str(out / f"{name}.wav"), "wb") as file:
        file.setnchannels(1); file.setsampwidth(2); file.setframerate(RATE)
        file.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32767)) for s in render(notes)))
    print("Wrote", out / f"{name}.wav")
