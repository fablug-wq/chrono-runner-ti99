# Chrono Runner for TI-99/4A

TI-99/4A port of the MSX platformer **Chrono Runner** by [Associazione MSX Italia](https://msxitalia.org), written in [CVBasic](https://github.com/nanochess/CVBasic) with the time-critical parts in TMS9900 assembly.

The game is complete: logo and splash, menu, intro, 29 levels plus 4 secret ones, interludes and cutscenes, final boss and ending, music and sound effects.

- Original game (MSX, C with MSXgl): https://github.com/AssociazioneMsxItalia/Chrono-runners
- TI-99/4A port: Fabrizio Luglio

## Playing

The cartridge is 128 KB, 8 KB non-inverted banks, and requires the **32K memory expansion**.

- **Classic99, js99er, FinalGROM:** file `chrono_chrono_8.bin`
- **MAME:** file `chrono_chrono_8.rpk`, for example with `mame ti99_4a -ioport peb -ioport:peb:slot3 32kmem -cart1 chrono_chrono_8.rpk`

The compiled files are in the repository's *Releases*.

## Building

You need:

- [CVBasic](https://github.com/nanochess/CVBasic) **0.9.2**: with versions earlier than 0.9.0 the game won't start;
- [xdt99](https://github.com/endlos99/xdt99), for the `xas99.py` assembler;
- Python 3.

```sh
./build.sh            # game  -> out/chrono_chrono_8.bin and .rpk
./build.sh viewer     # level viewer -> out/chrono_viewer_8.bin and .rpk
```

The tool directories are set with `CVBASIC_DIR` (default `~/tools/CVBasic`) and `XDT99_DIR` (default `~/tools/xdt99`).

The piano sound uses a volume table modified in CVBasic's `cvbasic_9900_prologue.asm`: described further below, in the Audio section. Without the change the game still works, with notes that sustain longer.

The files in `generated/` are already in place, so building doesn't require the MSX source. To regenerate them from the original repository: `MSX_SRC=/path/to/Chrono-runners ./build.sh`.

## Controls

- Menu: joystick up/down or E/W (up) and X/S (down); fire, space or ENTER to select. The TI arrow keys (FCTN+E/X) don't work: CVBasic's keyboard scan with FCTN held sees only FCTN. In Classic99 the PC arrow keys are the joystick, which is why they work there
- Joystick 1: left/right to run, up (or CTRL) to jump, fire (or space) held down to rewind
- FCTN+L: skip the level or interlude (test cheat, `CHEAT_ENABLED` in `game.bas`)
- FCTN+B: during play, jump straight to the final boss (same cheat)
- M: music on/off, in the menu and during play (turned back on, the track restarts from the beginning; sound effects are unaffected). It's also noted on the first page of the instructions, where ESC became FCTN+9
- FCTN+QUIT (FCTN+=): returns to the TI's startup screen, even during play
- FCTN+9 (BACK): skips the cutscene, like ESC on the MSX. At startup the intro notes this with a second line ("PRESS FCTN+9 TO SKIP INTRO"); the '+', missing from the MSX font, is drawn in tile 99 (free) by `plus_tile` in `chrono.bas`
- Keyboard: A/D (or S/D, matching the TI arrows) to run, W or E to jump, space to rewind. During play the keys are read directly from the matrix, so they also work together (jumping while running)

## Audio

**Music.** The 5 original PT3 modules (`sound/*.pt3`) are converted by `tools/audio2cvb.py` into CVBasic `MUSIC` sequences (`generated/bank_audio.bas`) and played with `PLAY FULL NO DRUMS`: three tone channels, noise is left for the effects. One tracker row = one `MUSIC` row, at the same speed (50 Hz ticks).

| Track | When | Bank |
|---|---|---|
| `mus_menu` (german4) | menu | 11 |
| `mus_intro` (impox160) | intro and final cutscenes | 11 |
| `mus_game` (game_bitslower) | from the first interlude onward, also in mid-world cutscenes | 10 |
| `mus_boss` (hitlerfinale) | boss; stops when it dies | 11 |
| `mus_gameover` | GAME OVER, once only (THE END is silent) | 10 |

Limits of the CVBasic player compared to PT3: no per-note volumes, ornaments, effects or envelopes. Notes weaker than 6 (the echoes) become rests; each note lasts at most `NOTE_TICKS` ticks (currently 16, about 0.3 s), then is cut off; notes below A2 (110 Hz, the SN76489's limit) are raised an octave. Instrument used: piano (`W`) on all channels; changeable via `INSTR` in `tools/audio2cvb.py`.

The piano (`W`) uses a custom volume curve, chosen by ear: it must be edited by hand in CVBasic's `cvbasic_9900_prologue.asm` (`pianovol1` table) and redone if CVBasic is updated:

```
pianovol1
    byte 12,12,11,11,10,10,9,9
    byte 8,7,6,5,4,3,2,1
    byte 0,0,0,0,0,0,0,0
```

Each note starts loud and fades out on its own over about 15 ticks, with no background hum.

`music_select` (in `generated/audio.bas`) changes the track and can be called from any bank: it switches to the music bank, does `PLAY`, then restores the previous bank.

**Effects.** The 15 AYFX effects (`content/ayfx/fx_chronorunner.h`) are translated frame by frame into SN76489 registers (bank 12, 3 bytes per frame). As on the MSX they play on channel C: for as long as the effect lasts, the fast interrupt rewrites channel C after the music, which takes the channel back at the end. Noise is used only by the effects. `GOSUB sfx_play` with `sfx_id = FX_...` (constants as in `fx_sounds.h`); a new effect interrupts the one in progress, as in the original.

Effects only work with the fast interrupt (i.e. always except in the menu, where the original doesn't use any either).

Speed: `MUSIC_60HZ` in `chrono.bas` (currently 1) plays music and effects at 60 ticks per second, as the original does on a 60 Hz MSX; with 0 they run at 50, as on a European MSX. `MUSIC_SLOW` (currently 10) only slows the music by skipping one tick every N frames: 10 = 10% slower (54 ticks per second), 20 = 5%, 0 = no slowdown. In the menu, where CVBasic's standard interrupt runs, `menu_wait` adjusts its skip counter to get the same pace.

The fast interrupt doesn't use CVBasic's `music_hardware`: `mh_chan` only writes changed frequencies and volumes to the chip, and skips channel C when it belongs to the effect. Audio cost: about 2,000 cycles per frame.

`tools/sn2wav.py` rebuilds a WAV from the chip writes recorded by `tools/ti99emu.py` (`sndlog`), useful for checks without Classic99.

## Timing and performance

The logic runs at 50 steps per second: the main loop skips one video frame out of every 6. Physics, the clock and the rewind duration remain those of the original on a European MSX.

If a step takes longer than one frame, the next one starts immediately instead of waiting for the next frame (`#fdone` in `chrono.bas`): the delay is made up, and the frame skipped every 6 acts as a buffer. The game only slows down if a step averages more than 1.2 frames; previously a single step that was just slightly too long was enough to lose a whole frame.

Every step must fit in one frame (about 50,000 cycles at 3 MHz). To achieve this:

- during play a lightweight interrupt runs (`fastisr.bas`): no full keyboard scan, and only the sprites in use are copied, with no anti-flicker rotation (as on the MSX). The menu keeps CVBasic's standard one;
- the cycles spent on objects are in TMS9900 assembly inside `game.bas`: updating and drawing enemies, fields and platforms, collisions with enemies, fields and mines, rewind snapshots. Each block is commented with a description of the original logic.

Measurements with `tools/ti99emu.py` (estimated cycles): a step costs about 22,000 cycles in empty levels and up to about 40,000 in the busiest ones; all levels tested complete 100 steps out of 100 in 2 seconds.

In the assembly parts, constants are written already computed: the TI assembler evaluates expressions left to right with no operator precedence (`>5800+12*32` equals `(>5800+12)*32`).

Caution: `fastisr.bas` uses CVBasic 0.9.2's internal labels (`sprites`, `joy1_data`, `frame`, `lfsr`, `music_*`, `audio_*`, `ay2sn`). This needs rechecking if CVBasic is updated.

## Contents

| Path | What it contains |
|---|---|
| `generated/ami.bas` | Associazione MSX Italia logo (ShowAmi, Screen 1), shown by `show_ami` before the splash with the line "TI994A port by Fabrizio Luglio" |
| `splash_data.bas` | Splash in Pletter-compressed bitmap (bank 13), loaded by `show_splash` in `chrono.bas` |
| `chrono.bas` | Main program: menu and 50 Hz game loop |
| `game.bas` | Player, physics, platforms, objects, HUD, clock, death |
| `ui.bas` | Menu, instructions, rating, credits, input utilities |
| `fastisr.bas` | Lightweight interrupt for gameplay and direct key reading |
| `cutscene.bas` | Cutscene interpreter (bytecode generated from the original scripts) |
| `flow.bas` | Game sequence, interlude, GAME OVER and THE END |
| `boss.bas` | Final boss: poses drawn with tiles, projectile, vortexes, 5 hits (code in bank 9) |
| `tools/audio2cvb.py` | PT3 music → CVBasic `MUSIC`, and AYFX effects → SN76489 (`generated/audio.bas`, `generated/bank_audio.bas`) |
| `tools/pt3parse.py` | PT3 module reader used by `audio2cvb.py` |
| `tools/sn2wav.py` | WAV from SN76489 writes recorded by the emulator |
| `tools/ti99emu.py` | Minimal TMS9900 + VDP emulator to test and profile the cartridge without Classic99 |
| `viewer.bas` | Level viewer (`./build.sh viewer`) |
| `tools/gen_tables.py` | GetDPos physics tables (`generated/tables.bas`) |
| `generated/` | Generated CVBasic sources (don't edit by hand) |
| `generated/report.txt` | Level order, each one's bank, sprite constants |
| `tools/msx2cvb.py` | Converter from the MSX repo to `.bas` files |
| `tools/preview.py` | Rebuilds screens as PNG from the generated `.bas` files |
| `build.sh` | Build: cvbasic → xas99 → linkticart → name into banks → RPK |
| `tools/name_replace.py` | Cartridge name across all banks |
| `tools/make_rpk.py` | RPK image for MAME |
| `HANDOFF.md` | Full technical document, for anyone modifying the port |

**Manual build:** with 10 or more banks xas99 numbers files with two digits. `linkticart` must be given `chrono_b00.bin` (no longer `chrono_b0.bin`), otherwise it links the banks from an old build.

## Viewer controls (`./build.sh viewer`)

- Right or `N`: next level
- Left or `P`: previous level
- Fire or space: back to menu

In Classic99 joystick 1 is on the arrow keys, with Tab as fire.

## Bank layout

| CVBasic bank | Content | Free |
|---|---|---|
| 0 (fixed, 24K in RAM) | code, tables, `common.bas`, `audio.bas` | ~2.8 KB |
| 1 | tileset (256 patterns + colors) and 64 sprites | ~1.9 KB |
| 2–4 | levels 0–26 (9 per bank) | ~350 bytes each |
| 5 | levels 27–32 (finale + 4 secrets) | ~2.9 KB |
| 6 | menu, credits, rating, interlude | ~1.7 KB |
| 7 | cutscene screens | ~0.5 KB |
| 8 | cutscene scripts | ~4.5 KB |
| 9 | boss: arena, poses and all of `boss.bas`'s code | ~2.3 KB |
| 10 | music: game, game over | ~2.2 KB |
| 11 | music: menu, boss, intro | ~5 KB |
| 12 | sound effects | ~3.3 KB |
| 13 | compressed splash (patterns and colors, 2.9 KB) and AMI logo (0.5 KB) | ~4.7 KB |

With `BANK ROM 128` bank 13 is the last one available.

The boss code lives in bank 9 to leave room in bank 0: from bank 0 it's called with `BANK SELECT BOSS_BANK` before `GOSUB boss_init` / `boss_step`.

## Level data format

The map is 32×22 tiles and is copied with `SCREEN` from row 2 (offset 64).

The object record is 113 bytes, read by `read_level_obj` into these variables:

- `lvl_start_x/y`, `lvl_end_x/y`, `lvl_key_x/y`, `lvl_crys_x/y`: coordinates in tiles
- `lvl_ktrig`: -1 if the key is visible right away, otherwise the index of the enemy that must be hit
- `lvl_nplat`, `plat_x/y/dx/dy/minx/miny/maxx/maxy()`: platforms, in pixels
- `lvl_nmine`, `mine_x/y()`: mines, in pixels
- `lvl_nenemy`, `enemy_x/y/dir/minx/maxx/type()`: enemies, in pixels
- `lvl_name_len`, `lvl_name()`: name already converted to tile indices

`plat_dx`, `plat_dy`, `enemy_dir` and `lvl_ktrig` are `SIGNED`.

## Regenerating

```sh
MSX_SRC=/path/to/Chrono-runners-main ./build.sh
```

## Licenses

- **Code** (hand-written `.bas` files, `build.sh`, `tools/`): GPLv3, see `LICENSE`.
- **Assets** (graphics, levels, music, effects, in-game text), contained in `generated/` and `splash_data.bas`: © Associazione MSX Italia, CC BY-NC-SA 4.0, see `ASSETS-LICENSE.md`.
- `fast_isr` in `fastisr.bas` is partly derived from CVBasic's `int_handler`, © Oscar Toledo G. (nanochess.org), with tursilion's TI-99/4A support, BSD license: see `THIRD-PARTY.md`.
