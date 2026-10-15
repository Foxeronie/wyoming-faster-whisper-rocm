FROM rocm/pytorch:rocm7.0_ubuntu24.04_py3.12_pytorch_release_2.7.1

LABEL org.opencontainers.image.source="https://github.com/Donkey545/wyoming-faster-whisper-rocm"

ARG CTRANSLATE2_REPO=https://github.com/pigeek/CTranslate2-rocm.git
ARG CTRANSLATE2_REF=rocm
ARG AMDGPU_TARGETS

ENV ROCM_PATH=/opt/rocm \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /src

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

# Only the build script is copied here so that changes to the application code
# do not invalidate the (very slow) CTranslate2 build layer.
COPY src/build.sh /src/build.sh

# Clone the ROCm CTranslate2 fork with submodules, build and install it, then
# remove the sources in the same layer so they do not end up in the image.
RUN (git clone --branch "${CTRANSLATE2_REF}" --depth 1 --recurse-submodules "${CTRANSLATE2_REPO}" /opt/build/CTranslate2 \
     || (rm -rf /opt/build/CTranslate2 \
         && git clone --branch "${CTRANSLATE2_REF}" --depth 1 "${CTRANSLATE2_REPO}" /opt/build/CTranslate2 \
         && git -C /opt/build/CTranslate2 submodule update --init --recursive)) \
 && AMDGPU_TARGETS="${AMDGPU_TARGETS:-}" \
    CTRANSLATE2_SRC_DIR=/opt/build/CTranslate2 \
    CTRANSLATE2_BUILD_DIR=/opt/build/CTranslate2/build \
    CTRANSLATE2_INSTALL_PREFIX=/usr/local \
    PYTHON_BIN=python3 \
    /src/build.sh \
 && rm -rf /opt/build

# Runtime requirements. ctranslate2 is pinned to the version built above so pip
# cannot replace the ROCm build with the CUDA wheel from PyPI.
RUN CT2_VERSION="$(python3 -c 'import ctranslate2; print(ctranslate2.__version__)')" \
 && pip install "ctranslate2==${CT2_VERSION}" "wyoming~=1.6" "faster-whisper~=1.0" "tokenizers>=0.15,<0.21" \
 && python3 -c 'import ctranslate2; print("ctranslate2", ctranslate2.__version__, "from", ctranslate2.__file__)'

# Application code
COPY src/run.sh /src/run.sh
COPY src/wyoming_whisper /src/wyoming_whisper

ENV PYTHONPATH=/src

VOLUME ["/data"]
EXPOSE 10300

ENTRYPOINT ["/src/run.sh"]
