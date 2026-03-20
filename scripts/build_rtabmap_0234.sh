#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RTABMAP_SRC_DIR="$ROOT_DIR/third_party/rtabmap-0.23.4"
RTABMAP_BUILD_DIR="$RTABMAP_SRC_DIR/build_local"
RTABMAP_INSTALL_DIR="$RTABMAP_SRC_DIR/install"
JOBS="${JOBS:-4}"

detect_opencv_dir() {
  local candidates=()
  local pc_dir=""

  if [[ -n "${RTABMAP_OPENCV_DIR:-}" ]]; then
    candidates+=("${RTABMAP_OPENCV_DIR}")
  fi
  if [[ -n "${OpenCV_DIR:-}" ]]; then
    candidates+=("${OpenCV_DIR}")
  fi

  if command -v pkg-config >/dev/null 2>&1; then
    pc_dir="$(pkg-config --variable=pcfiledir opencv4 2>/dev/null || true)"
    if [[ -n "$pc_dir" ]]; then
      candidates+=("${pc_dir%/pkgconfig}/cmake/opencv4")
    fi
  fi

  candidates+=(
    "/usr/lib/aarch64-linux-gnu/cmake/opencv4"
    "/usr/lib/x86_64-linux-gnu/cmake/opencv4"
    "/usr/local/lib/cmake/opencv4"
    "/usr/local/lib64/cmake/opencv4"
    "/usr/lib/cmake/opencv4"
  )

  local d
  for d in "${candidates[@]}"; do
    if [[ -n "$d" && -f "$d/OpenCVConfig.cmake" ]]; then
      echo "$d"
      return 0
    fi
  done

  local found
  found="$(find /usr /usr/local -type f -path '*/cmake/opencv4/OpenCVConfig.cmake' 2>/dev/null | head -n 1 || true)"
  if [[ -n "$found" ]]; then
    dirname "$found"
    return 0
  fi

  return 1
}

OPENCV_DIR="$(detect_opencv_dir || true)"
if [[ -z "$OPENCV_DIR" ]]; then
  echo "[ERROR] OpenCVConfig.cmake not found. Set RTABMAP_OPENCV_DIR manually." >&2
  exit 10
fi

if [[ ! -f "$RTABMAP_SRC_DIR/CMakeLists.txt" ]]; then
  echo "[ERROR] RTABMap source not found at: $RTABMAP_SRC_DIR" >&2
  exit 1
fi

# Basic version sanity check
MAJOR=$(grep -E "^SET\(RTABMAP_MAJOR_VERSION" "$RTABMAP_SRC_DIR/CMakeLists.txt" | sed -E 's/.*RTABMAP_MAJOR_VERSION ([0-9]+).*/\1/')
MINOR=$(grep -E "^SET\(RTABMAP_MINOR_VERSION" "$RTABMAP_SRC_DIR/CMakeLists.txt" | sed -E 's/.*RTABMAP_MINOR_VERSION ([0-9]+).*/\1/')
PATCH=$(grep -E "^SET\(RTABMAP_PATCH_VERSION" "$RTABMAP_SRC_DIR/CMakeLists.txt" | sed -E 's/.*RTABMAP_PATCH_VERSION ([0-9]+).*/\1/')
VER="${MAJOR}.${MINOR}.${PATCH}"

if [[ "$VER" != "0.23.4" ]]; then
  echo "[ERROR] Expected RTABMap 0.23.4, got ${VER}" >&2
  exit 2
fi

mkdir -p "$RTABMAP_BUILD_DIR"
rm -rf "$RTABMAP_BUILD_DIR/CMakeFiles"
rm -f "$RTABMAP_BUILD_DIR/CMakeCache.txt"

CMAKE_ARGS=(
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_INSTALL_PREFIX="$RTABMAP_INSTALL_DIR"
  -DBUILD_APP=OFF
  -DBUILD_TOOLS=OFF
  -DBUILD_EXAMPLES=OFF
  -DWITH_TORCH=OFF
  -DWITH_PYTHON=OFF
  -DWITH_CUDASIFT=OFF
  -DWITH_ZED=OFF
  -DWITH_ZEDOC=OFF
  -DOpenCV_DIR="$OPENCV_DIR"
)

echo "[INFO] OpenCV_DIR     = $OPENCV_DIR"
echo "[INFO] Building RTABMap ${VER}"
cmake -S "$RTABMAP_SRC_DIR" -B "$RTABMAP_BUILD_DIR" "${CMAKE_ARGS[@]}"

cmake --build "$RTABMAP_BUILD_DIR" -j"$JOBS"
cmake --install "$RTABMAP_BUILD_DIR"

RTABMAP_CONFIG=$(find "$RTABMAP_INSTALL_DIR" -name RTABMapConfig.cmake | head -n 1 || true)
if [[ -z "$RTABMAP_CONFIG" ]]; then
  echo "[ERROR] RTABMapConfig.cmake not found under $RTABMAP_INSTALL_DIR" >&2
  exit 3
fi

RTABMAP_DIR="$(dirname "$RTABMAP_CONFIG")"

if grep -R -q -E 'opencv_cudaoptflow|opencv_cudaimgproc' "$RTABMAP_DIR"; then
  missing=0
  if ! find /usr /usr/local -type f -name 'libopencv_cudaoptflow.so*' 2>/dev/null | grep -q .; then
    echo "[ERROR] RTABMap exports opencv_cudaoptflow but libopencv_cudaoptflow is not installed." >&2
    missing=1
  fi
  if ! find /usr /usr/local -type f -name 'libopencv_cudaimgproc.so*' 2>/dev/null | grep -q .; then
    echo "[ERROR] RTABMap exports opencv_cudaimgproc but libopencv_cudaimgproc is not installed." >&2
    missing=1
  fi
  if [[ "$missing" -eq 1 ]]; then
    echo "[HINT] Check OpenCVConfig source or set RTABMAP_OPENCV_DIR to a non-CUDA OpenCV config." >&2
    exit 4
  fi
fi

echo "[DONE] RTABMap installed to: $RTABMAP_INSTALL_DIR"
echo "[NEXT] Run: source \"$ROOT_DIR/scripts/use_rtabmap_0234_env.sh\""
echo "[INFO] RTABMap_DIR = $RTABMAP_DIR"
