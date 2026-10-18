HCrafter sounds

By default HCrafter plays the game's own sound effects, read from your own
game folder and kept as .wav copies in config\addons\hcrafter\sounds. None
of the game's audio ships with HCrafter. When the game's folder can't be
found, each alert plays one of the sounds below instead.

These ten sounds were made for HCrafter from plain sine tones by a small
script (tools/make_sounds.py in the source). No samples or recordings from
the game or anywhere else are used. They ship under HCrafter's license.

  ready.wav     Chime: two soft chimes (synths done)
  chimes.wav    Three chimes stepping up (startup)
  bell.wav      Bell: one warm, slow bell (no more skill-ups)
  dingdong.wav  Ding-dong: two notes stepping down (shutdown)
  blip.wav      Blip: one short high note (skill-ups)
  alert.wav     Alert: two notes back and forth (out of a material)
  levelup.wav   Level-up: a rising chord (level-ups)
  hq.wav        HQ sparkle (HQs)
  hq_big.wav    Big HQ (rare HQs)
  break.wav     Break: two low notes (breaks have no sound by default)

Pick the sound for each alert in the recipe book, under Settings, Fanfare
and sounds. Your own .wav files in this folder show up in those lists too.
Set the volume there, or turn every sound off with "Play sounds".

Your own files follow the volume when they are PCM (8, 16, 24 or 32-bit)
or 32-bit float, mono or stereo, and up to 10 seconds long at 48 kHz.
Others play at their own volume. HCrafter keeps at most 40 copies in
config\addons\hcrafter\sounds, deleting the oldest first but never the
ones in use, and deletes copies whose sound file changed.
