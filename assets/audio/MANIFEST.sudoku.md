# Audio assets manifest

`AudioManager` looks up clips by **id** and resolves them to actual `.mp3`
filenames via internal mapping tables (`SFX_NAMES`, `MUSIC_NAMES`). Missing
files are a silent no-op — the game runs fine without them.

## SFX — `assets/audio/sfx/` (short, one-shot, quiet)

| id | file | when it plays | feel |
|------|------|----------------|------|
| `tap` | `button.mp3` | cell select | soft, short click |
| `click` | `button.mp3` | generic UI button (GlowButton) | subtle UI tick |
| `place` | `correct block.mp3` | correct number placed | satisfying confirm |
| `error` | `wrong block.mp3` | wrong number placed | gentle negative blip |
| `win` | `victory.mp3` | puzzle solved | bright success chime |
| `gameover` | `game over.mp3` | puzzle lost (mistakes) | soft defeat cue |

Keep SFX **mono**, ~0.1–0.6 s, normalized but not loud.

## Music / ambience — `assets/audio/music/` (seamless loops)

All import files have `loop=true`. Theme `ambience_id` values map to these ids.
Default is no music (`""` = "Follow theme" in Settings).

| id | file | mood |
|------|------|------|
| `piano` | `piano.mp3` | calm solo piano |
| `lofi` | `lofi.mp3` | lofi beats |
| `rain` | `rain.mp3` | rain ambience |
| `cafe` | `cafe.mp3` | coffee-shop chatter |
| `forest` | `forest.mp3` | birds / wind |
| `temple` | `temple.mp3` | zen / singing bowls |
| `whitenoise` | `white noise.mp3` | steady white noise |
| `fireplace` | `fireplace.mp3` | crackling fire |
