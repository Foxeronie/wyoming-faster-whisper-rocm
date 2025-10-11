FROM rocm/pytorch:rocm7.0_ubuntu24.04_py3.12_pytorch_release_2.7.1

LABEL org.opencontainers.image.source="https://github.com/Donkey545/wyoming-faster-whisper-rocm"

ARG CTRANSLATE2_REPO=https://github.com/pigeek/CTranslate2-rocm.git
ARG CTRANSLATE2_REF=rocm
ARG AMDGPU_TARGETS

ENV ROCM_PATH=/opt/rocm \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /opt/build

# Build dependencies for CTranslate2
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    git \
    cmake \
    ninja-build \
    build-essential \
    python3-dev \
    patchelf \
    libomp-dev \
    ffmpeg \
    pkg-config \
 && rm -rf /var/lib/apt/lists/*

COPY src /src

# Clone ROCm CTranslate2 fork with submodules
RUN git clone --branch "${CTRANSLATE2_REF}" --depth 1 --recurse-submodules "${CTRANSLATE2_REPO}" /opt/build/CTranslate2 \
 || (git clone --branch "${CTRANSLATE2_REF}" --depth 1 "${CTRANSLATE2_REPO}" /opt/build/CTranslate2 && cd /opt/build/CTranslate2 && git submodule update --init --recursive)

RUN AMDGPU_TARGETS="${AMDGPU_TARGETS:-}" \
    CTRANSLATE2_SRC_DIR=/opt/build/CTranslate2 \
    CTRANSLATE2_BUILD_DIR=/opt/build/CTranslate2/build \
    CTRANSLATE2_INSTALL_PREFIX=/usr/local \
    PYTHON_BIN=python3 \
    /src/build.sh

# Runtime requirements
RUN pip install "wyoming~=1.6" "faster-whisper~=1.0" "tokenizers>=0.15,<0.21"

# Copy application code and configure runtime
WORKDIR /src
RUN rm -rf /opt/build

ENV PYTHONPATH=/src

VOLUME ["/data"]
EXPOSE 10300

ENTRYPOINT ["/src/run.sh"]
