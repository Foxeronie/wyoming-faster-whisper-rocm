#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="${CTRANSLATE2_SRC_DIR:-/opt/build/CTranslate2}"
BUILD_DIR="${CTRANSLATE2_BUILD_DIR:-${SRC_DIR}/build}"
INSTALL_PREFIX="${CTRANSLATE2_INSTALL_PREFIX:-/usr/local}"
HIP_ARCH_LIST="${AMDGPU_TARGETS:-gfx900;gfx902;gfx906;gfx908;gfx90a;gfx1010;gfx1030;gfx1100;gfx1101;gfx1102;gfx1151}"
PYTHON_BIN="${PYTHON_BIN:-python3}"

for tool in git cmake hipconfig "${PYTHON_BIN}"; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "Required tool '${tool}' is not available in PATH." >&2
    exit 1
  fi
done

if [ ! -d "${SRC_DIR}" ]; then
  echo "CTranslate2 sources not found at ${SRC_DIR}. Set CTRANSLATE2_SRC_DIR or clone before running build.sh." >&2
  exit 1
fi

echo "==> Configuring build"
LLVM_BIN="$(hipconfig -l)"
HIP_ROOT="$(hipconfig -R)"
JOBS="$(command -v nproc >/dev/null 2>&1 && nproc || echo 1)"

cmake -S "${SRC_DIR}" -B "${BUILD_DIR}" \
  -DWITH_MKL=OFF \
  -DWITH_HIP=ON \
  -DBUILD_TESTS=OFF \
  -DWITH_CUDNN=ON \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}" \
  -DCMAKE_PREFIX_PATH="${ROCM_PATH:-/opt/rocm}" \
  -DCMAKE_HIP_ARCHITECTURES="${HIP_ARCH_LIST}" \
  -DCMAKE_HIP_COMPILER_FLAGS="--amdgpu-target=${HIP_ARCH_LIST//;/ --amdgpu-target=}" \
  -DCMAKE_C_COMPILER="${LLVM_BIN}/amdclang" \
  -DCMAKE_CXX_COMPILER="${LLVM_BIN}/amdclang++" \
  -DCMAKE_HIP_COMPILER="${LLVM_BIN}/amdclang" \
  -DHIP_ROOT_DIR="${HIP_ROOT}"

echo "==> Building CTranslate2"
cmake --build "${BUILD_DIR}" --parallel "${JOBS}"

echo "==> Installing CTranslate2 to ${INSTALL_PREFIX}"
cmake --install "${BUILD_DIR}" --prefix "${INSTALL_PREFIX}"

if command -v ldconfig >/dev/null 2>&1; then
  echo "==> Refreshing shared library cache"
  ldconfig
fi

echo "==> Building Python wheel"
${PYTHON_BIN} -m pip install -U pip setuptools wheel pybind11
${PYTHON_BIN} -m pip install -r "${SRC_DIR}/python/install_requirements.txt"
(
  cd "${SRC_DIR}/python"
  ${PYTHON_BIN} setup.py bdist_wheel
  ${PYTHON_BIN} -m pip install dist/ctranslate2-*.whl
)

echo "==> Build complete"
