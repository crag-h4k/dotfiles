<!-- docs/sounds.md -->
# Notification sounds

## Table of Contents

- [Overview](#overview)
- [Auditioning](#auditioning)
- [Candidate sounds (2026-09-14)](#candidate-sounds-2026-09-14)
- [Original sounds](#original-sounds)
- [Constraints](#constraints)
- [Adding a sound](#adding-a-sound)

## Overview

`home/dot_config/notify/sounds/*.mp3` holds every sound the tmux attention
notifier can play. Files are committed directly, not fetched through
`.chezmoiexternal.toml`, so this repository redistributes them. This document is
the provenance record: source URL and licence for each file.

Assignment of a sound to a group lives in
`home/dot_config/notify/notify.yaml.tmpl`, not here. See
[Notifications](notifications.md).

## Auditioning

```sh
scripts/audition-sounds.sh          # every sound, from the chezmoi source tree
scripts/audition-sounds.sh --new    # only sounds no group references yet
scripts/audition-sounds.sh --live   # what is installed under ~/.config
scripts/audition-sounds.sh --say    # speak each name before playing it
scripts/audition-sounds.sh -v 40 --gap 2 chime-up bell wood-knock
```

The script sources `lib.sh` and calls `notify_play`, so the player chain and the
volume-to-gain conversion are identical to a real notification. It sets
`$NOTIFY_SOUNDS` to redirect `notify_play` at the source tree, which is the only
reason that override exists.

## Candidate sounds (2026-09-14)

Twenty candidates, all Creative Commons Zero, all from Kenney. CC0 is a public
domain dedication: no attribution is required and redistribution in this public
repository is unrestricted. Credit is recorded anyway because provenance is the
point of this file.

Every file was converted from Vorbis `.ogg` to MP3, trimmed of leading and
trailing silence below -60 dB, and gain-matched to -24 LUFS integrated with a
-3 dBTP ceiling. See [Adding a sound](#adding-a-sound) for the exact command.

| File | Character | Source pack | Original |
| --- | --- | --- | --- |
| `airlock-hiss.mp3` | Pneumatic release, air-band hiss decaying | Sci-fi Sounds | `doorOpen_002.ogg` |
| `bell.mp3` | Struck bell, low-mid, long decay | Impact Sounds | `impactBell_heavy_003.ogg` |
| `bonk.mp3` | Deep short bonk, near-instant decay | Interface Sounds | `bong_001.ogg` |
| `buzz-low.mp3` | Low negative buzz | Interface Sounds | `error_006.ogg` |
| `chime-up.mp3` | Bright two-note ascending chime | Interface Sounds | `confirmation_002.ogg` |
| `chime-warm.mp3` | Warm mid-range two-note confirmation | Interface Sounds | `confirmation_004.ogg` |
| `coin-jingle.mp3` | Coins handled, high and airy, no low end | RPG Audio | `handleCoins.ogg` |
| `data-chatter.mp3` | Computer data chatter, 0.8 s excerpt | Sci-fi Sounds | `computerNoise_001.ogg` |
| `latch.mp3` | Crisp metal latch click | RPG Audio | `metalLatch.ogg` |
| `pluck.mp3` | Single plucked string | Interface Sounds | `pluck_002.ogg` |
| `query-blip.mp3` | Short interrogative blip | Interface Sounds | `question_004.ogg` |
| `query-rise.mp3` | Interrogative rising two-note | Interface Sounds | `question_001.ogg` |
| `rasp.mp3` | Broadband negative rasp | Interface Sounds | `error_003.ogg` |
| `retro-zap.mp3` | Retro descending laser zap | Sci-fi Sounds | `laserRetro_004.ogg` |
| `sweep-down.mp3` | Falling airy sweep | Interface Sounds | `minimize_004.ogg` |
| `sweep-up.mp3` | Rising airy sweep | Interface Sounds | `maximize_004.ogg` |
| `three-tone.mp3` | Three pure tones | Digital Audio | `threeTone1.ogg` |
| `thunk.mp3` | Chunky mechanical switch | Interface Sounds | `switch_005.ogg` |
| `two-tone.mp3` | Two pure tones | Digital Audio | `twoTone1.ogg` |
| `wood-knock.mp3` | Dry wood knock, fast decay | Impact Sounds | `impactWood_medium_002.ogg` |

`data-chatter.mp3` is the only derived excerpt: the source is a 5 s steady loop,
cut at 1.00-1.80 s with a 15 ms fade in. CC0 permits the modification.

### Source packs

| Pack | URL | Licence |
| --- | --- | --- |
| Interface Sounds | <https://kenney.nl/assets/interface-sounds> | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| Digital Audio | <https://kenney.nl/assets/digital-audio> | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| Sci-fi Sounds | <https://kenney.nl/assets/sci-fi-sounds> | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| Impact Sounds | <https://kenney.nl/assets/impact-sounds> | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| RPG Audio | <https://kenney.nl/assets/rpg-audio> | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) |

Each pack ships a `License.txt` stating CC0 1.0 and noting that credit to Kenney
is appreciated but not mandatory.

## Original sounds

The twelve sounds that predate this record. Provenance was reconstructed by
inspection, not from a contemporaneous note, so the "Origin" column is a
best-effort attribution rather than a verified chain.

| File | Origin | Licence status |
| --- | --- | --- |
| `funk.mp3` | Apple macOS system sound (`Funk.aiff`) | Proprietary. Apple asserts copyright over system sounds; redistribution is not licensed. |
| `glass.mp3` | Apple macOS system sound (`Glass.aiff`) | Proprietary, as above. |
| `sosumi.mp3` | Apple macOS system sound (`Sosumi.aiff`) | Proprietary, as above. |
| `submarine.mp3` | Apple macOS system sound (`Submarine.aiff`) | Proprietary, as above. |
| `return-by-death.mp3` | Audio clip, apparent anime source | Unknown. No licence recorded. |
| `alert.mp3` | Unrecorded | Unknown. |
| `boom.mp3` | Unrecorded | Unknown. |
| `chirp.mp3` | Unrecorded | Unknown. |
| `swoosh.mp3` | Unrecorded | Unknown. |
| `sword.mp3` | Unrecorded | Unknown. |
| `toot.mp3` | Unrecorded | Unknown. |
| `whip.mp3` | Unrecorded | Unknown. |

The four Apple sounds are the clearest exposure. They ship with macOS under the
macOS software licence agreement, which does not grant redistribution rights, and
this repository is public. The practical risk is low and the files have been here
since the subsystem was written, but the exposure is real and undocumented until
now. Three options, in order of preference:

1. Replace them with CC0 equivalents from the candidate set and delete the
   originals from the working tree and from git history.
2. Replace them going forward and leave history alone, accepting that the blobs
   remain reachable by SHA.
3. Keep them and accept the risk knowingly.

The remaining eight are unattributed rather than known-proprietary. They should
either get provenance or get replaced.

## Constraints

Any new sound has to satisfy all of these.

| Constraint | Requirement | Why |
| --- | --- | --- |
| Format | MP3 only | The player chain is `afplay`, then `mpg123`, then `ffplay`. `mpg123` decodes MP3 only, so any other container breaks Debian. |
| Duration | Roughly 0.1 s to 1.5 s | Fires on every finished turn. Anything long or musical becomes intolerable within a day. |
| Loudness | -24 LUFS integrated, true peak at or below -3 dBTP | Matches the existing set, which clusters between -23 and -26 LUFS. Gain is applied once at build time; `notify_play` then scales by the group's 0-100 volume. |
| Licence | CC0 or public domain preferred | Public repository. Anything requiring attribution must be recorded in this file. |
| Distinctness | Audibly different from every other sound in the directory | The whole point is knowing which tool wants you without looking. Differing gesture (rise, fall, pluck, knock) separates better than differing timbre alone. |
| Encoding | 44.1 kHz, 128 kbps CBR, `libmp3lame` | Matches the existing files and is maximally decodable. |

`scripts/validate-templates.sh` asserts that every `sound:` named in the rendered
notify config exists in this directory. Adding files is always safe; renaming or
deleting one that a group references fails the pre-commit hook.

## Adding a sound

Convert and gain-match in one pass. Measure the source first, because `loudnorm`
cannot compute integrated loudness on clips under 3 s without padding:

```sh
src=source.ogg
# 1. Trim silence below -60 dB from both ends, downmix to mono 44.1 kHz.
ffmpeg -i "$src" -af \
  'silenceremove=start_periods=1:start_duration=0:start_threshold=-60dB:detection=peak,areverse,silenceremove=start_periods=1:start_duration=0:start_threshold=-60dB:detection=peak,areverse' \
  -ar 44100 -ac 1 /tmp/trimmed.wav

# 2. Measure. apad makes the clip long enough for integrated loudness; the
#    silence is below the -70 LUFS absolute gate, so it does not skew the result.
ffmpeg -i /tmp/trimmed.wav -af 'apad=pad_dur=4,loudnorm=print_format=json' -t 8 -f null -

# 3. gain = -24 - input_i, clamped so input_tp + gain stays at or below -3.
ffmpeg -i /tmp/trimmed.wav -af 'volume=<gain>dB,afade=t=out:st=<dur-0.012>:d=0.012' \
  -ar 44100 -ac 1 -codec:a libmp3lame -b:a 128k -write_xing 1 \
  home/dot_config/notify/sounds/<name>.mp3
```

Then verify and audition:

```sh
ffmpeg -v warning -i home/dot_config/notify/sounds/<name>.mp3 -f null -   # must be silent
scripts/audition-sounds.sh <name>
```

Name the file for what it sounds like, lowercase and hyphenated, not for the
group it is assigned to. Assignments change; the sound does not. Record the
source URL and licence in the table above in the same commit.
