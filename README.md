# Wyoming Faster Whisper ROCm

## Quick Description
Faster Whisper running on AMD GPUs with the ROCm build of CTranslate2, served up with the Wyoming protocol

This is a fork of [pigeek/wyoming-faster-whisper-rocm](https://github.com/pigeek/wyoming-faster-whisper-rocm), which is based on [Donkey545/wyoming-faster-whisper-rocm](https://github.com/Donkey545/wyoming-faster-whisper-rocm). See [Changes in this fork](#changes-in-this-fork) for what is different.


## System Overview

This project ties together a few projects to make Faster Whisper work with an AMD GPU. It was originally built for an AMD APU (5650G).

### Host System & Hardware Requirements
- AMD GPU or APU with an architecture `gfx900` or newer
	- Check your architecture [here](https://llvm.org/docs/AMDGPUUsage.html) if you don't know
- About 20 GB of free disk space (the source build needs more temporarily).
- [ROCm Installed ](https://rocm.docs.amd.com/projects/install-on-linux/en/latest/index.html)
- [Docker Installed](https://docs.docker.com/desktop/install/linux-install/)
- [Docker Compose Plugin Installed](https://docs.docker.com/compose/install/linux/)
### Services Required to Use this Service
- [HomeAssistant](https://www.home-assistant.io/)
	- [Wyoming Addon](https://www.home-assistant.io/integrations/wyoming/)

### Tools to Make your Life Easier
- [btop](https://github.com/aristocratos/btop)
	- Great for CPU and Memory Monitoring
- [AMDGPU_TOP](https://github.com/Umio-Yasuno/amdgpu_top)
	- Excellent Command Line Utility for Viewing GPU utilization. 

## Project Components

- [Wyoming](https://pypi.org/project/wyoming/)
- [Faster Whisper](https://pypi.org/project/faster-whisper/)
- [CTranslate2](https://github.com/OpenNMT/CTranslate2)
	- Supports AMD GPUs via ROCm/HIP since version 4.7. The official ROCm wheels cover `gfx1030`, `gfx1100`-`gfx1102`, `gfx1150`/`gfx1151` and `gfx1200`/`gfx1201`.
	- For other architectures (e.g. `gfx90c` APUs) the image can build CTranslate2 from source for your GPU.
- [ROCm](https://rocm.docs.amd.com/) 7.2
	- The runtime image is based on `ubuntu:24.04` and only contains the ROCm libraries CTranslate2 needs (no PyTorch).


## Instructions:

1. Clone this repository and open the directory

```bash
git clone https://github.com/Foxeronie/wyoming-faster-whisper-rocm.git
cd wyoming-faster-whisper-rocm/
```

2. Find your GPU architecture:

```bash
rocminfo | grep " gfx"   # e.g. gfx1100 for an RX 7900 XTX
```

   - Covered by the official wheel (`gfx1030`, `gfx1100`-`gfx1102`, `gfx1150`/`gfx1151`, `gfx1200`/`gfx1201`): nothing to do.
   - Anything else (e.g. `gfx90c`): build CTranslate2 from source for your architecture. This takes a while.

```bash
export CTRANSLATE2_SOURCE=source
export AMDGPU_TARGETS=gfx900   # gfx90c runs the gfx900 code with HSA_OVERRIDE_GFX_VERSION=9.0.0
```

   Also check `WYOMING_MODEL`/`WYOMING_COMPUTE_TYPE` in `docker-compose.yml`. The default `large-v3-turbo` with `float16` needs a few GB of VRAM; on small GPUs/APUs use e.g. `medium` with `int8`.

3. Run Docker Compose
``` bash
docker compose up -d --build
```
At this point you can configure the Whisper service with Wyoming in home assistant with the `<dockerhost_ip_address>:10300`.

### Useful Environment Variables

- During build:
  - `CTRANSLATE2_SOURCE` (`wheel` (default) or `source`)
  - `AMDGPU_TARGETS` (only for `source`, semicolon separated, e.g. `gfx900;gfx1010`)
- At runtime the container entrypoint reads several optional variables:
  - `WYOMING_MODEL` (default `distil-small.en`)
  - `WYOMING_DEVICE` (default `cuda`)
  - `WYOMING_COMPUTE_TYPE` (default `default`)
  - `WYOMING_DATA_DIRS` (colon separated list, default `/data`)
  - `WYOMING_DOWNLOAD_DIR` (defaults to the first data dir)
  - `WYOMING_LANGUAGE` (e.g. `de`, `de-DE` or `auto`), `WYOMING_BEAM_SIZE`, `WYOMING_INITIAL_PROMPT`, `WYOMING_EXTRA_ARGS`
  - `WYOMING_DEBUG` (set to `1` to enable debug logging)
  - `CT2_CUDA_ALLOCATOR` (default `cub_caching`, see [Changes in this fork](#changes-in-this-fork))
  - `HSA_OVERRIDE_GFX_VERSION` (for GPUs/APUs not officially supported by ROCm, e.g. `9.0.0` for `gfx90c`)

### Running as a non-root user
If you set `user:` in your compose file, the container needs access to the GPU device nodes and a writable cache location:
- Add the host's group IDs of `/dev/kfd` and `/dev/dri/renderD*` via `group_add` (check them with `ls -ln /dev/kfd /dev/dri`). Group names like `video` are resolved inside the container and may not match the host.
- Point the caches to the data volume, e.g. `HOME=/data`, `HF_HOME=/data/hf` and `XDG_CACHE_HOME=/data/cache`.

### Debugging
You can shell into the container if you need to experiment:
```bash
docker compose exec whisper bash
```
From there you can run `python -m wyoming_whisper --help` to view live CLI options.


## Changes in this fork

Compared to [pigeek/wyoming-faster-whisper-rocm](https://github.com/pigeek/wyoming-faster-whisper-rocm):

### CTranslate2 and Docker image
- **Official CTranslate2 instead of a fork:** CTranslate2 supports ROCm upstream since 4.7. By default the image now installs the official ROCm wheel of CTranslate2 4.8.3 (download is verified by SHA-256) instead of compiling the [pigeek/CTranslate2-rocm](https://github.com/pigeek/CTranslate2-rocm) fork. Nothing is compiled for supported GPUs.
- **Optional source build:** `CTRANSLATE2_SOURCE=source` builds upstream CTranslate2 for `AMDGPU_TARGETS` on top of `rocm/dev-ubuntu-24.04`, for GPUs the official wheel does not cover (e.g. `gfx90c`). `build.sh` was rewritten for this and produces a self-contained wheel.
- **Much smaller image:** The runtime image is now `ubuntu:24.04` with only the ROCm 7.2.4 libraries CTranslate2 links against, instead of the full `rocm/pytorch` image (about 68 GB). PyTorch is not needed by faster-whisper.
- **Build cache:** Application code is copied last, so code changes no longer invalidate the expensive layers.
- **GPU allocator:** CTranslate2 uses `hipMallocAsync` on ROCm by default, which fails model loading with "out of memory" even with free VRAM. The image sets `CT2_CUDA_ALLOCATOR=cub_caching`.
- **Pinned dependencies:** `faster-whisper==1.2.1`, `wyoming==1.10.2` and `av==18.1.0` are pinned (PyAV 19 removed an argument faster-whisper 1.2.1 still uses); the outdated `tokenizers<0.21` cap and the bundled `ctranslate2-4.1.0-cp39` wheel were removed. Python packages live in a virtualenv (`/opt/venv`).

### Wyoming server
- **Model lock fixed:** faster-whisper generates segments lazily, so decoding used to run after the model lock was released. The transcription is now fully consumed inside the lock and runs in a worker thread, keeping the event loop responsive.
- **Robustness:** An `audio-stop` without preceding audio returns an empty transcript instead of crashing the handler; errors during transcription are logged and answered with an empty transcript, so the client does not wait for a timeout; transcripts no longer contain double spaces.
- **Language codes:** Codes like `de-DE` or `pt_BR` (from Home Assistant or `WYOMING_LANGUAGE`) are mapped to what Whisper understands (`de`, `pt`). Unsupported languages fall back to auto-detection instead of failing the transcription.
- **Reported languages:** Home Assistant is told the languages of the loaded model (only `en` for `.en` models) instead of a fixed list.
- Updated attribution to [SYSTRAN/faster-whisper](https://github.com/SYSTRAN/faster-whisper), removed unused code.

### Configuration and tooling
- `run.sh`: removed the legacy conda activation and the no-op HSA override, added `WYOMING_DEBUG`.
- `docker-compose.yml`: build arguments `CTRANSLATE2_SOURCE`/`AMDGPU_TARGETS`, defaults to `large-v3-turbo` with `float16`, documents useful environment variables.
- pre-commit: replaced the broken poetry-based black/ruff hooks with [ruff-pre-commit](https://github.com/astral-sh/ruff-pre-commit) and updated `pre-commit-hooks`.
- README: updated requirements, instructions and environment variables.
