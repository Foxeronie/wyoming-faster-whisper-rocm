# Wyoming Faster Whisper ROCm

## Quick Description
Faster Whisper running on AMD GPUs with the ROCm build of CTranslate2, served up with the Wyoming protocol


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
git clone https://github.com/Donkey545/wyoming-faster-whisper-rocm.git
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
  - `HSA_OVERRIDE_GFX_VERSION` (for GPUs/APUs not officially supported by ROCm, e.g. `9.0.0` for `gfx90c`)

### Debugging
You can shell into the container if you need to experiment:
```bash
docker compose exec whisper bash
```
From there you can run `python -m wyoming_whisper --help` to view live CLI options.
