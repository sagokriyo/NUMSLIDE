# Ambience

The looping ambience beds now live in **`../music/`** (shared with background
music) and are mapped by id in [audio_manager.gd](../../../autoload/audio_manager.gd)
`AMBIENCE_PATHS`: `rain, piano, cafe, forest, lofi, temple, fireplace`, plus
`space` (reuses `white noise.mp3`). They are selectable on the Settings → Audio
tab; "Off" stops the bed.

This folder is kept as the conventional drop-spot if you later want to separate
ambience from music — point `AMBIENCE_PATHS` here and move the files.
