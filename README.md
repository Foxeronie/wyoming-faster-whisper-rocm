# Wyoming Faster Whisper ROCm

## Quick Description
Faster whisper Running on AMD GPUs with modified CTranslate 2 Libraries served up with Wyoming protocol


## System Overview

This project ties together a few projects to make Faster Whisper work with an AMD GPU. This has only been built for an AMD APU (5650G) at this time.

### Host System & Hardware Requirements
- AMD GPU or APU with an architecture `gfx900` or newer
	- - Check you architecture [here](https://llvm.org/docs/AMDGPUUsage.html) if you don't know
- At least 100gb of disk space.
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
- [ROCm/Pytorch](https://hub.docker.com/r/rocm/pytorch)
	- Build Requires Python 3.9, the project makes use of the 20.04 image.
- [CTranslate2-rocm](https://github.com/pigeek/CTranslate2-rocm)
	- This project is essential to running Faster Whisper as the standard CTranslate2 Library does not support ROCm natively. 
	- This project needs to be built to the GPU architecture specific to your hardware.

**Note:** The docker image required for this project is massive. On my system it is showing as 68g.4b.


## Instructions:

1. Clone this repository and open the directory

```bash
git clone https://github.com/Donkey545/wyoming-faster-whisper-rocm.git
cd wyoming-faster-whisper-rocm/
```

2. Optional: export the GPU architecture you want CTranslate2 to target. The image already builds support for several common targets (`gfx900`, `gfx902`, `gfx906`, `gfx908`, `gfx90a`, `gfx1010`, `gfx1030`, `gfx1100`, `gfx1101`, `gfx1102`, `gfx1151`), but setting this keeps build times down and ensures your exact arch is present.

```bash
rocminfo | grep " gfx"   # find your architecture, e.g., gfx90c
export AMDGPU_TARGETS=gfx90c
```

3. Run Docker Compose
``` bash
docker compose up -d --build
```
At this point you can configure the Whisper service with Wyoming in home assistant with the `<dockerhost_ip_address>:10300`.

### Useful Environment Variables

- During build you can set `AMDGPU_TARGETS` (for example `export AMDGPU_TARGETS=gfx1100` before running compose) so CTranslate2 compiles specifically for your GPU.
- At runtime the container entrypoint reads several optional variables:
  - `WYOMING_MODEL` (default `distil-small.en`)
  - `WYOMING_DEVICE` (default `cuda`)
  - `WYOMING_COMPUTE_TYPE` (default `default`)
  - `WYOMING_DATA_DIRS` (colon separated list, default `/data`)
  - `WYOMING_DOWNLOAD_DIR` (defaults to the first data dir)
  - `WYOMING_LANGUAGE`, `WYOMING_BEAM_SIZE`, `WYOMING_INITIAL_PROMPT`, `WYOMING_EXTRA_ARGS`

### Optional Manual Build
The container now builds CTranslate2 automatically. You can still shell into the container if you need to experiment:
```bash
docker compose exec whisper bash
```
From there you can run `python -m wyoming_whisper --help` to view live CLI options.
