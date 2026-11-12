# firefox-edge-tts

Use [edge-tts](https://github.com/rany2/edge-tts) — Microsoft Edge's online
neural text-to-speech service — for Firefox ESR Reader Mode on Debian 13,
replacing the robotic espeak-ng narration.

The chain this wires up:

```
firefox-esr  ->  speech-dispatcher  ->  sd_generic  ->  edge-tts  ->  mpg123  ->  pw-cat
```

> **Edge TTS is online-only.** Every utterance is synthesised by Microsoft's
> service, so narration requires internet access and the article text is sent to
> Microsoft. There is no local fallback: when the service is unreachable,
> narration stops. `edge-tts` is also an unofficial client for an endpoint
> Microsoft can change or block at any time.

Everything installs **per-user**: nothing is written to `/etc`, and the only root
access is `apt` for packages Debian already expects you to have. Uninstall
restores your previous configuration and leaves espeak-ng working.

## Requirements

- Debian 13 (trixie). The script refuses to run on other releases.
- `firefox-esr` from apt
- Internet access to Microsoft's speech endpoint
- An audio player: `pw-cat` (PipeWire, recommended), `paplay`, or `aplay`
- `python3`, `python3-venv`, `jq`, `mpg123` (the installer apt-installs any that
  are missing)

`mpg123` is required because edge-tts produces MP3, while the speech-dispatcher
module plays raw PCM.

## Quick start

```sh
git clone <this-repo> && cd firefox-edge-tts
./firefox-edge-tts.sh --install
```

The installer fetches the voice catalogue, shows a menu, installs edge-tts in a
private Python environment, wires it into speech-dispatcher, and verifies the
result.

Then **close Firefox** and point its Narrate feature at the new voice:

```sh
./firefox-edge-tts.sh --set-firefox-voice
```

Reopen Firefox, open an article, press `Ctrl+R` for Reader Mode, then `V` to
narrate.

> **Firefox must be closed for `--set-firefox-voice`.** Firefox rewrites its
> profile preferences from memory when it exits, so a change made while it is
> running is silently discarded. The script refuses to edit rather than appear to
> succeed and lose the change.

## Commands

| Command | What it does |
| --- | --- |
| `--install` | Install edge-tts, fetch the voice catalogue, and configure speech-dispatcher |
| `--install --voice NAME` | Install without the interactive menu, e.g. `bg-BG-BorislavNeural` |
| `--set-firefox-voice` | Point Firefox's Narrate at edge-tts (**close Firefox first**) |
| `--test` | Verify the chain end to end |
| `--status` | Show what is installed |
| `--list-voices` | List voices in the cached catalogue |
| `--refresh-voices` | Re-fetch the voice catalogue from Microsoft |
| `--uninstall` | Remove edge-tts and restore espeak-ng |
| `--cleanup-piper` | Remove a leftover `firefox-piper` install (after edge-tts works) |

`--uninstall` accepts `--purge-packages` (also remove the speech-dispatcher apt
packages). Without that flag, espeak-ng is deliberately left working as the
default voice. `mpg123` and `jq` are left in place either way.

Uninstall restores your previous `speechd.conf` and removes the edge-tts module,
runtime, generated bridge, and cached catalogue. Only a config this project did
not write is used as a backup, and a backup still loading a generated module is
discarded rather than restored — otherwise speech-dispatcher would be left
pointing at a runtime that has just been deleted and unable to speak. Re-running
`--install` is safe: it never overwrites your original config with its own.

Running the script with no arguments prints this help.

## What gets installed

| Path | Contents |
| --- | --- |
| `~/.local/share/edge-tts/venv/` | Private Python environment holding `edge-tts` |
| `~/.local/share/edge-tts/bin/edge-tts` | Generated wrapper that execs the venv |
| `~/.local/share/edge-tts/edge-speak` | Generated bridge: text → edge-tts → mpg123 → raw PCM |
| `~/.cache/firefox-edge-tts/voices.json` | Cached voice catalogue |
| `~/.config/speech-dispatcher/speechd.conf` | Generated main config (prior one backed up) |
| `~/.config/speech-dispatcher/modules/edge-tts.conf` | Generated `sd_generic` module config |

The previous `speechd.conf` is saved as `speechd.conf.firefox-edge-tts.bak` and
restored on uninstall.

The wrapper is intentionally **not** `~/.local/bin/edge-tts`, so it does not
shadow an edge-tts command you may already have installed.

## Voices

Voices are served by Microsoft's speech service, so nothing is downloaded and
there are no model files to checksum. The catalogue is fetched at install time
and cached, and it reports each voice's locale and gender directly. That means:

- no 60 MiB voice downloads;
- no hand-maintained gender table;
- `--list-voices` shows the catalogue, and `--refresh-voices` updates it.

The default is `bg-BG-BorislavNeural` (Bulgarian, male). Pass `--voice` with any
catalogue short name to use another, for example `bg-BG-KalinaNeural` or
`en-US-AriaNeural`.

Gender and locale from the catalogue decide the speech-dispatcher voice type
(`MALE1`, `FEMALE1`, …) and the language Firefox matches on. The voice is
registered under the bare language code (`bg`), not the full locale.

## Latency

The first word arrives after roughly 1 second on a warm connection, and after
about 2–3 seconds on the first request. This is higher than Piper's ~0.4 s
model-load time because each utterance starts a new Python process and a new
request to Microsoft. Streaming is progressive — audio starts before the whole
clip has arrived — so articles remain usable, but short strings feel slower.

## Online and privacy caveats

- **The text is sent to Microsoft.** Do not use this for articles or documents
  you would not send to a third-party service.
- **No offline mode.** With no network, narration produces silence. `--test`
  reports the failure; the module log has the details.
- **Unofficial client.** edge-tts generates Edge's DRM-style tokens and spoofs
  Edge headers. Microsoft has changed this endpoint before, and can block it
  again. Keep the package updated.
- **Clock skew can cause 403 errors.** The service validates a time-derived
  token; make sure the system clock is correct (`timedatectl`).
- **No rate-limit handling.** Long articles send many requests in quick
  succession. If the service throttles you, narration will pause or fail.

## Upgrading edge-tts

edge-tts is installed with pip, so it can be upgraded on its own:

```sh
~/.local/share/edge-tts/venv/bin/pip install --upgrade edge-tts
```

Run `./firefox-edge-tts.sh --install` afterwards to regenerate the wrapper and
verify the service still works. The installer also upgrades automatically when
the installed version is older than the minimum it supports.

## Migrating from firefox-piper

The older project can coexist on disk while you try this one. After
`--install` works, remove its files with:

```sh
./firefox-edge-tts.sh --cleanup-piper
```

This removes the Piper runtime, wrapper, `piper.conf`, its state file, and only
the voices that `firefox-piper` itself installed. A real original
`speechd.conf.firefox-piper.bak` is adopted as this project's restore point
first, so uninstalling later still brings back the true original config.
`--cleanup-piper` refuses to run until edge-tts is configured, so
speech-dispatcher is never left pointing at a deleted module.

## Notes

**`spd-say -L` does not list stock voices the way espeak's module does.** That is
normal for an `sd_generic` module and not a sign of failure; the voice is
registered through `AddVoice`.

**Audio player.** `pw-play` cannot be used here: it takes a filename, not a PCM
stream, so piping into it fails. The script uses `pw-cat --playback --raw`
instead, falling back to `paplay` or `aplay`.

**Decoding.** edge-tts always returns MP3 at 24 kHz mono. `edge-speak` pipes it
through `mpg123 -m -r 24000 -s`, forcing mono and 24 kHz so the player pipeline
never has to know about the service's format.

**Rate.** speech-dispatcher's `-100..100` rate is mapped to edge-tts's
`[+-]N%`; out-of-range values are clamped. The module config must use
`GenericRateMultiply 100`, not `1`: DotConf has no float type, so `sd_generic`
divides the value by 100 as soon as it is read. Pitch and volume are currently
left at speech-dispatcher's defaults.

## How it works

edge-tts is exposed to speech-dispatcher as an `sd_generic` module. The module
receives text on a pipe, hands it to the generated `edge-speak` wrapper, and
streams raw PCM to the audio player.

Four details were found by testing against speech-dispatcher 0.12.1 rather
than assumed, and each one breaks narration if wrong:

- **`$DATA` must be single-quoted** in `GenericExecuteSynth`. The double-quoted
  form mangles apostrophes in article text (`it's` arrives as `it'\''s`) and
  silently strips double quotes.
- **`GenericMaxChunkLength` must be raised.** `sd_generic` defaults to cutting
  every 300 bytes — mid-word, with no regard for sentence structure — and
  synthesizes each piece separately. Firefox sends a whole paragraph as one
  utterance, so the config raises the limit to 64 KiB and sets
  `GenericDelimiters "|"` (a character that does not occur in text) to disable
  delimiter splitting. edge-tts then does its own word-boundary chunking and
  streams the result.
- **`GenericDefaultCharset "utf-8"` is required.** Without it, `sd_generic`
  recodes the utterance and every non-Latin character becomes `?` — which
  destroys Bulgarian text entirely.
- **Voices must be registered under the bare language code** (`bg`, not `bg-BG`).
  Firefox's Narrate UI filters voices with `v.lang.split("-")[0] == language` and
  hides the Listen button entirely when nothing matches.

Firefox also stores its narration voice in the `narrate.voice` preference as a
JSON map of language to voice URI. It keeps requesting whatever voice it had
before, so `--set-firefox-voice` updates that map (preserving voices for other
languages) rather than relying on the module default.

## Troubleshooting

**No Listen button in Reader Mode.** Check that the voice is visible:

```sh
spd-say -L | grep Borislav      # language column must read "bg", not "bg-BG"
```

**Narration sounds robotic.** Firefox is still using espeak-ng. Confirm
`narrate.voice` points at edge-tts:

```sh
grep narrate.voice ~/.mozilla/firefox/*/prefs.js
```

Then close Firefox and re-run `--set-firefox-voice`.

**Narration cuts off mid-word or sounds choppy.** The module config was written
with `sd_generic`'s default 300-byte chunk limit, which splits words and
synthesizes each fragment separately. Re-run `--install` to regenerate it; the
generated `edge-tts.conf` should contain:

```sh
GenericMaxChunkLength 65536
GenericDelimiters "|"
```

**Narration speed does not change.** Firefox's speed slider arrives at
speech-dispatcher as `-100..100`, but a mis-scaled `GenericRateMultiply` makes
every value look the same. Re-run `--install` (the generated `edge-tts.conf`
should say `GenericRateMultiply 100`), then restart Firefox.

**Nothing is spoken, or `--test` reports no audio.** Check the network and the
service:

```sh
~/.local/share/edge-tts/bin/edge-tts --list-voices | head
```

Check the module log at
`$XDG_RUNTIME_DIR/speech-dispatcher/log/edge-tts.log`. A 403 usually means clock
skew or an outdated edge-tts; run `timedatectl` and upgrade the package.

**Voice shows under the wrong name or gender.** Refresh the catalogue with
`--refresh-voices`; the voice URI in `narrate.voice` must match the
speech-dispatcher registration exactly.

**`--set-firefox-voice` says Firefox is running when it is not.** It matches the
process name, not the full command line, so this should not happen — if it does,
check for a stray `firefox` process with `pgrep -ax firefox`.

**Audio is wrong speed or pitch.** The decoder forces 24 kHz mono; if the service
changes its output, upgrade edge-tts and re-run `--install`.

## License

`edge-tts` is downloaded at install time and is licensed under the LGPLv3 (with
an MIT-licensed SRT helper). The speech service and voices are Microsoft's and
are subject to Microsoft's terms; this project is not affiliated with Microsoft.
