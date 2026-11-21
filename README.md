# Daphile

Lyrion Music Server (LMS) plugin porting the *Daphile OS* extras: Daphile transcoding rules and helpers, per-player audio processing options and a system information page.

## Features
- **Daphile transcoding rules** (`daphile-convert.conf`): optional replacement of the stock `convert.conf` rules by the Daphile `Transcode` / `Decode` helpers. Applied immediately; disabling restores the stock rules (setting *Use Daphile transcoding rules*).
- **DSD**: DSD-over-PCM (DoP) per player for DACs that support it, and optional PCM to DSD (dsf) conversion.
- **HLS** (`m3u8`) streams.
- **Audio processing** per player: resampling on the media server, maximum sample rate, HDCD decoder and pre-emphasis handling.
- **Daphile Info** pages: system status and log file viewer.
- Helper binaries in `Bin/x86_64-linux` (`Transcode`, `Decode`, `DoP-encode`, `Native+`, `info.sh`, `metadata.sh`, ...).

## Requirements
- Lyrion Music Server 9.x on x86_64 Linux
- `sox`, `ffmpeg`, `ffprobe` and `jq` for the Daphile transcoding rules

## Installation
Copy the `Daphile` folder into the `Plugins` directory of the server cache (for example `/config/cache/Plugins`), restart Lyrion, then enable the plugin settings under *Settings > Plugins > Daphile* and per player under *Settings > Player*.

## Files
| File | Purpose |
| --- | --- |
| `Plugin.pm` | Plugin entry point, loads the Daphile rules into the transcoding tables |
| `Settings.pm`, `PlayerSettings.pm`, `HTML/` | Server and player settings pages |
| `Info.pm` | System status and logs pages |
| `daphile-convert.conf`, `custom-types.conf` | Transcoding rules and file types |
| `Bin/` | Helper programs used by the rules |
| `strings.txt` | Text strings |

## Version
1.0

## Author
nicos
