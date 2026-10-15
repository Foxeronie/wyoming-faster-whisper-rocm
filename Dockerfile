# syntax=docker/dockerfile:1

ARG UBUNTU_VERSION=24.04
ARG ROCM_VERSION=7.2.4
# Where the ROCm build of CTranslate2 comes from:
#   wheel  - official ROCm wheel from the CTranslate2 release page. Supports
#            gfx1030, gfx1100-gfx1102, gfx1150/gfx1151 and gfx1200/gfx1201.
#   source - build CTranslate2 for AMDGPU_TARGETS, e.g. for older GPUs/APUs
#            such as gfx900/gfx90c that the official wheel does not cover.
ARG CTRANSLATE2_SOURCE=wheel
ARG CTRANSLATE2_VERSION=4.8.3

# -----------------------------------------------------------------------------

FROM ubuntu:${UBUNTU_VERSION} AS ctranslate2-wheel

ARG CTRANSLATE2_VERSION
# SHA-256 of rocm-python-wheels-Linux.zip. Must be updated together with
# CTRANSLATE2_VERSION (or set to an empty string to skip the check).
ARG CTRANSLATE2_WHEELS_SHA256=132eda022faed55e4d1a7093f15a9dd9d4bcdf26bd72471ec1c984bada9a3d3f
# Must match the python3 of the runtime image (Ubuntu 24.04: 3.12)
ARG PYTHON_TAG=cp312

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    unzip \
 && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /tmp/wheels.zip \
    "https://github.com/OpenNMT/CTranslate2/releases/download/v${CTRANSLATE2_VERSION}/rocm-python-wheels-Linux.zip" \
 && if [ -n "${CTRANSLATE2_WHEELS_SHA256}" ]; then \
      echo "${CTRANSLATE2_WHEELS_SHA256}  /tmp/wheels.zip" | sha256sum -c -; \
    fi \
 && mkdir /wheels \
 && unzip -j /tmp/wheels.zip "*/ctranslate2-*-${PYTHON_TAG}-${PYTHON_TAG}-*.whl" -d /wheels \
 && rm /tmp/wheels.zip

# -----------------------------------------------------------------------------

FROM rocm/dev-ubuntu-${UBUNTU_VERSION}:${ROCM_VERSION}-complete AS ctranslate2-source

ARG CTRANSLATE2_VERSION
ARG CTRANSLATE2_REPO=https://github.com/OpenNMT/CTranslate2.git
ARG AMDGPU_TARGETS

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    git \
    cmake \
    ninja-build \
    python3-dev \
    python3-venv \
 && rm -rf /var/lib/apt/lists/* \
 && python3 -m venv /opt/build-venv

COPY src/build.sh /src/build.sh

RUN git clone --branch "v${CTRANSLATE2_VERSION}" --depth 1 \
    --recurse-submodules --shallow-submodules \
    "${CTRANSLATE2_REPO}" /opt/build/CTranslate2 \
 && AMDGPU_TARGETS="${AMDGPU_TARGETS:-}" \
    PYTHON_BIN=/opt/build-venv/bin/python \
    /src/build.sh \
 && rm -rf /opt/build

# -----------------------------------------------------------------------------

FROM ctranslate2-${CTRANSLATE2_SOURCE} AS ctranslate2

# -----------------------------------------------------------------------------

FROM ubuntu:${UBUNTU_VERSION}

ARG ROCM_VERSION

LABEL org.opencontainers.image.source="https://github.com/Foxeronie/wyoming-faster-whisper-rocm"

# CTranslate2 defaults to the async allocator (hipMallocAsync) on ROCm, which
# fails model loading with "out of memory" even with free VRAM (seen on an
# RX 7900 XTX with ROCm 7.2.4). The caching allocator works.
ENV ROCM_PATH=/opt/rocm \
    CT2_CUDA_ALLOCATOR=cub_caching \
    PATH=/opt/venv/bin:${PATH} \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Only the ROCm runtime libraries CTranslate2 links against (plus their
# dependencies) instead of a full ROCm/PyTorch image. hiprand does not declare
# its dependency on rocrand, and libdrm from the amdgpu repo is installed
# outside the default library path, so both are handled explicitly.
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    python3 \
    python3-venv \
 && . /etc/os-release \
 && mkdir -p /etc/apt/keyrings \
 && curl -fsSL https://repo.radeon.com/rocm/rocm.gpg.key | gpg --dearmor -o /etc/apt/keyrings/rocm.gpg \
 && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/${ROCM_VERSION} ${VERSION_CODENAME} main" \
    > /etc/apt/sources.list.d/rocm.list \
 && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/graphics/${ROCM_VERSION}/ubuntu ${VERSION_CODENAME} main" \
    > /etc/apt/sources.list.d/amdgpu.list \
 && printf 'Package: *\nPin: release o=repo.radeon.com\nPin-Priority: 600\n' > /etc/apt/preferences.d/rocm-pin-600 \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    hipblas \
    hiprand \
    rocrand \
 && apt-get purge -y --auto-remove curl gnupg \
 && rm -rf /var/lib/apt/lists/* \
 && printf '/opt/rocm/lib\n/opt/amdgpu/lib/x86_64-linux-gnu\n' > /etc/ld.so.conf.d/rocm.conf \
 && ldconfig

# Runtime requirements. The ROCm build of ctranslate2 is installed from the
# local wheel in the same step, so pip cannot pull the CUDA wheel from PyPI.
# av is capped because PyAV 19 removed the metadata_errors argument that
# faster-whisper 1.2.1 passes to av.open().
RUN --mount=type=bind,from=ctranslate2,source=/wheels,target=/tmp/wheels \
    python3 -m venv /opt/venv \
 && pip install \
    /tmp/wheels/ctranslate2-*.whl \
    "faster-whisper==1.2.1" \
    "av==18.1.0" \
    "wyoming==1.10.2" \
 && python3 -c 'import ctranslate2; print("ctranslate2", ctranslate2.__version__, "from", ctranslate2.__file__)'

# Application code
COPY src/run.sh /src/run.sh
COPY src/wyoming_whisper /src/wyoming_whisper

ENV PYTHONPATH=/src

VOLUME ["/data"]
EXPOSE 10300

ENTRYPOINT ["/src/run.sh"]
