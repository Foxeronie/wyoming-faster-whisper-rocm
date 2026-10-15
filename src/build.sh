#!/usr/bin/env bash
# Builds a CTranslate2 Python wheel with ROCm/HIP support from source.
#
# Only needed for GPUs that are not covered by the official ROCm wheels
# (see the Dockerfile). The resulting wheel bundles libctranslate2 and the
# OpenMP runtime, the ROCm libraries are expected on the target system.
set -euo pipefail

SRC_DIR="${CTRANSLATE2_SRC_DIR:-/opt/build/CTranslate2}"
BUILD_DIR="${CTRANSLATE2_BUILD_DIR:-${SRC_DIR}/build}"
INSTALL_PREFIX="${CTRANSLATE2_INSTALL_PREFIX:-/usr/local}"
WHEEL_DIR="${CTRANSLATE2_WHEEL_DIR:-/wheels}"
HIP_ARCH_LIST="${AMDGPU_TARGETS:-gfx900;gfx906;gfx908;gfx90a;gfx942;gfx1030;gfx1100;gfx1101;gfx1102;gfx1151;gfx1200;gfx1201}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
ROCM_PATH="${ROCM_PATH:-/opt/rocm}"

for tool in cmake "${PYTHON_BIN}"; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "Required tool '${tool}' is not available in PATH." >&2
    exit 1
  fi
done

if [ ! -d "${SRC_DIR}" ]; then
  echo "CTranslate2 sources not found at ${SRC_DIR}. Set CTRANSLATE2_SRC_DIR or clone before running build.sh." >&2
  exit 1
fi

LLVM_BIN="${ROCM_PATH}/lib/llvm/bin"
JOBS="$(nproc 2>/dev/null || echo 1)"

echo "==> Configuring build for ${HIP_ARCH_LIST}"
cmake -S "${SRC_DIR}" -B "${BUILD_DIR}" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}" \
  -DCMAKE_PREFIX_PATH="${ROCM_PATH}" \
  -DCMAKE_C_COMPILER="${LLVM_BIN}/amdclang" \
  -DCMAKE_CXX_COMPILER="${LLVM_BIN}/amdclang++" \
  -DCMAKE_CXX_FLAGS="-Wno-deprecated-literal-operator" \
  -DCMAKE_HIP_FLAGS="-Wno-deprecated-literal-operator" \
  -DCMAKE_HIP_ARCHITECTURES="${HIP_ARCH_LIST}" \
  -DWITH_HIP=ON \
  -DWITH_MKL=OFF \
  -DOPENMP_RUNTIME=COMP \
  -DBUILD_CLI=OFF \
  -DBUILD_TESTS=OFF

echo "==> Building CTranslate2"
cmake --build "${BUILD_DIR}" --parallel "${JOBS}"
cmake --install "${BUILD_DIR}"
ldconfig

echo "==> Building Python wheel"
"${PYTHON_BIN}" -m pip install -r "${SRC_DIR}/python/install_requirements.txt" auditwheel patchelf
(
  cd "${SRC_DIR}/python"
  "${PYTHON_BIN}" -m pip wheel --no-deps --no-build-isolation -w dist .
)

# Bundle libctranslate2 and libomp into the wheel, but leave the ROCm
# libraries out: they come from the ROCm packages of the runtime image.
LD_LIBRARY_PATH="${INSTALL_PREFIX}/lib:${ROCM_PATH}/lib:${ROCM_PATH}/lib/llvm/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}" \
  "${PYTHON_BIN}" -m auditwheel repair \
  --plat "linux_$(uname -m)" \
  --exclude 'libamdhip64.so*' \
  --exclude 'libhipblas.so*' \
  --exclude 'libhiprand.so*' \
  -w "${WHEEL_DIR}" \
  "${SRC_DIR}"/python/dist/ctranslate2-*.whl

echo "==> Build complete"
ls -l "${WHEEL_DIR}"
