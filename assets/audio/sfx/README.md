# SFX

Real one-shot clips are bundled here (imported from the sibling project) and
mapped by id in [audio_manager.gd](../../../autoload/audio_manager.gd) `SFX_PATHS`:

| id | file | when it plays |
|----|------|----------------|
| `button_tap` | `button.mp3` | any UI button / tappable |
| `tile_move` | `menu button.mp3` | a move that shifts tiles |
| `tile_merge` | `block_merge.mp3` | tiles merge |
| `victory` | `win.wav` | a line made — in gameplay, and on Home's hero strip |
| `game_over` | `game over.mp3` | no moves / time out |
| `achievement` | `default bckground chime.mp3` | achievement unlock cue |
| `invalid` | `wrong block.mp3` | reserved for invalid moves |
| `opening` | `opening scene.mp3` | splash screen |

`AudioManager` loads lazily and no-ops on a missing file, so swapping clips is
safe. To retune the palette, change the filenames in `SFX_PATHS`.

Five further ids — `combo`, `streak`, `drop_land`, `whoosh`, `annihilate` — are
mapped but not yet authored; `AudioManager` memoises the miss and logs it once,
so they cost nothing until someone drops the files in.

`annihilate` is Antimatter's cancellation cue and wants the *inverse* shape of
`tile_merge`: a short inward collapse that shuts, rather than an impact that
lands. It plays instead of `tile_merge` on a swipe that only cancelled.

## Notes

* `win.wav` is the one clip NOT imported from the sibling project: it is **baked**
  by [tools/win_sting.py](../../../tools/win_sting.py), which is the only thing
  that may edit it. A four-note rising arpeggio (C6 E6 G6 C7) struck as bells —
  each note a fundamental plus three inharmonic partials, every partial decaying
  faster than the one below it — walking left to right across the stereo field,
  with two delayed attenuated copies for a room. 1.60 s, peak −1.5 dBFS, and the
  script is deterministic, so re-running it reproduces the file byte for byte.
  `victory.mp3` is still in this folder: putting it back is one line in
  `SFX_PATHS`.

* `default bckground chime.mp3` was re-encoded 2026-07-26 from CBR 256 kbps
  joint-stereo (1,757,100 B) to **CBR 128 kbps joint-stereo (879,429 B)** — same
  44.1 kHz, same stereo, same 54.909 s. Godot keeps an `AudioStreamMP3`
  compressed in memory, so the file size *is* the resident cost, and this clip
  was 22% of the whole shipped payload. Measured: the residual against the
  original is flat at ~−55 dBFS RMS anywhere between 64 and 128 kbps for this
  material (it only improves past 192 kbps), the source has no energy above
  15 kHz (−98 dBFS RMS) so the encoder lowpass removes nothing, and the L−R side
  channel is preserved to within 0.5 dB. 96 kbps measures identically and would
  save a further 219,846 B if anyone wants it.
* **It is still a 54.9-second ambient bed being used as a one-shot achievement
  sting, and `play_sfx()` never stops a voice** (`SFX_VOICES = 6`), so an
  achievement unlock plays music over gameplay until six further one-shots
  recycle that pool slot. Trimming it to a ~2 s cue is an audible change and
  needs a listening decision — it was deliberately NOT done here.
