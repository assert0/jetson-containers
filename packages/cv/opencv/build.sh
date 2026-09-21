#!/usr/bin/env bash
echo "Building opencv-python ${OPENCV_VERSION}"
set -ex
cd /opt

# install dependencies
bash $TMP/install_deps.sh

git clone --recursive https://github.com/opencv/opencv
cd /opt/opencv && git checkout --recurse-submodules ${OPENCV_VERSION}

cd /opt
git clone --recursive https://github.com/opencv/opencv_contrib
cd /opt/opencv_contrib && git checkout --recurse-submodules ${OPENCV_VERSION}

cd /opt
git clone --branch "${OPENCV_PYTHON}" --recursive https://github.com/opencv/opencv-python

# Check the OpenCV version from the opencv-python submodule
cd /opt/opencv-python/opencv
cat modules/core/include/opencv2/core/version.hpp

# apply patches to setup.py
git apply $TMP/patches.diff || echo "failed to apply git patches"
git diff

# OpenCV looks for the cuDNN version in cudnn_version.h, but it's been renamed to cudnn_version_v8.h
ln -sfnv /usr/include/$(uname -i)-linux-gnu/cudnn_version_v*.h /usr/include/$(uname -i)-linux-gnu/cudnn_version.h

# patches for FP16/half casts
# These patches are only needed for OpenCV versions < 4.10.0
# In 4.10.0+, the upstream code already has the fixes
function patch_opencv()
{
    # Check if the patches are needed by looking for the old patterns
    # Try multiple possible paths for the files
    local normalize_bbox_file=""
    local region_file=""
    
    # Try to find the files in common locations
    # These files are in the main opencv repo, not opencv_contrib
    for path in \
        "opencv/modules/dnn/src/cuda4dnn/primitives/normalize_bbox.hpp" \
        "modules/dnn/src/cuda4dnn/primitives/normalize_bbox.hpp" \
        "/opt/opencv/modules/dnn/src/cuda4dnn/primitives/normalize_bbox.hpp" \
        "/opt/opencv-python/opencv/modules/dnn/src/cuda4dnn/primitives/normalize_bbox.hpp"; do
        if [ -f "$path" ]; then
            normalize_bbox_file="$path"
            break
        fi
    done
    
    for path in \
        "opencv/modules/dnn/src/cuda4dnn/primitives/region.hpp" \
        "modules/dnn/src/cuda4dnn/primitives/region.hpp" \
        "/opt/opencv/modules/dnn/src/cuda4dnn/primitives/region.hpp" \
        "/opt/opencv-python/opencv/modules/dnn/src/cuda4dnn/primitives/region.hpp"; do
        if [ -f "$path" ]; then
            region_file="$path"
            break
        fi
    done
    
    # Apply patches if files exist and contain the old patterns
    if [ -n "$normalize_bbox_file" ] && grep -q 'weight != 1.0' "$normalize_bbox_file"; then
        sed -i 's|weight != 1.0|(float)weight != 1.0f|' "$normalize_bbox_file"
        echo "Applied weight != 1.0 patch to $normalize_bbox_file"
    else
        echo "normalize_bbox.hpp patch not needed (file not found or already fixed upstream)"
    fi
    
    if [ -n "$region_file" ] && grep -q 'nms_iou_threshold > 0' "$region_file"; then
        sed -i 's|nms_iou_threshold > 0|(float)nms_iou_threshold > 0.0f|' "$region_file"
        echo "Applied nms_iou_threshold > 0 patch to $region_file"
    else
        echo "region.hpp patch not needed (file not found or already fixed upstream)"
    fi
}

patch_opencv
cd /opt
patch_opencv
cd /opt/opencv-python

# default build flags
OPENCV_BUILD_ARGS="\
   -DCPACK_BINARY_DEB=ON \
   -DBUILD_EXAMPLES=OFF \
   -DBUILD_opencv_python2=OFF \
   -DBUILD_opencv_python3=ON \
   -DBUILD_opencv_java=OFF \
   -DCMAKE_BUILD_TYPE=RELEASE \
   -DCMAKE_INSTALL_PREFIX=/usr/local \
   -DWITH_FFMPEG=ON \
   -DCUDA_ARCH_BIN=${CUDA_ARCH_BIN} \
   -DCUDA_ARCH_PTX= \
   -DCUDA_FAST_MATH=ON \
   -DCUDNN_INCLUDE_DIR=/usr/include/$(uname -i)-linux-gnu \
   -DEIGEN_INCLUDE_PATH=/usr/include/eigen3 \
   -DWITH_EIGEN=ON \
   -DOPENCV_DNN_CUDA=ON \
   -DOPENCV_ENABLE_NONFREE=ON \
   -DOPENCV_GENERATE_PKGCONFIG=ON \
   -DOpenGL_GL_PREFERENCE=GLVND \
   -DWITH_CUBLAS=ON \
   -DWITH_CUDA=ON \
   -DWITH_CUDNN=ON \
   -DWITH_GSTREAMER=ON \
   -DWITH_LIBV4L=ON \
   -DWITH_GTK=ON \
   -DWITH_OPENGL=ON \
   -DWITH_OPENCL=OFF \
   -DWITH_IPP=OFF \
   -DWITH_TBB=ON \
   -DBUILD_TIFF=ON \
   -DBUILD_PERF_TESTS=OFF \
   -DBUILD_TESTS=OFF"

# architecture-specific build flags
if [ "$(uname -m)" == "aarch64" ]; then
    OPENCV_BUILD_ARGS="${OPENCV_BUILD_ARGS} -DENABLE_NEON=ON"
fi

# cv2.abi3.so: undefined symbol: glRenderbufferStorageEXT
# https://github.com/opencv/opencv_contrib/issues/2307
OPENCV_BUILD_ARGS="${OPENCV_BUILD_ARGS} -DBUILD_opencv_rgbd=OFF"

# setup environment and build wheel
export CMAKE_BUILD_PARALLEL_LEVEL=$(nproc)
export CMAKE_POLICY_VERSION_MINIMUM="3.5"
export CMAKE_LIBRARY_PATH=/usr/local/cuda/lib64/stubs
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH
export ENABLE_CONTRIB=1
# export ENABLE_ROLLING=1 # Build from last commit
# export OPENCV_PYTHON_SKIP_GIT_COMMANDS=1

# Install dependencies for building the wheel
uv pip install scikit-build

cat <<EOF > /opt/opencv-python/cv2/version.py
opencv_version = "${OPENCV_VERSION}"
contrib = True
headless = False
rolling = False
EOF
CMAKE_ARGS="${OPENCV_BUILD_ARGS} -DOPENCV_EXTRA_MODULES_PATH=/opt/opencv-python/opencv_contrib/modules" \
uv build --wheel --out-dir /opt --verbose --no-build-isolation .

ls /opt
cd /
rm -rf /opt/opencv-python

# install/test/upload wheel
uv pip install /opt/opencv*.whl
python3 -c "import cv2; print('OpenCV version:', str(cv2.__version__)); print(cv2.getBuildInformation())"
twine upload --verbose /opt/opencv*.whl || echo "failed to upload wheel to ${TWINE_REPOSITORY_URL}"

# [FIX] Ensure the build directory is clean to avoid CMake caching issues from previous failed runs.
echo "Configuring C++ Debian package build..."
rm -rf /opt/opencv/build
mkdir /opt/opencv/build
cd /opt/opencv/build

# [FIX] Fix any existing FFmpeg pkg-config files that reference /opt/ffmpeg/dist
if [ -d /usr/local/lib/pkgconfig ]; then
  echo "Fixing FFmpeg pkg-config files..."
  sed -i 's|/opt/ffmpeg/dist|/usr/local|g' /usr/local/lib/pkgconfig/*.pc 2>/dev/null || true
fi

# [FIX] Create /opt/ffmpeg/dist symlink if it doesn't exist (for backward compatibility)
if [ ! -d /opt/ffmpeg/dist ] && [ -d /usr/local/include ] && [ -d /usr/local/lib ]; then
  echo "Creating /opt/ffmpeg/dist symlink for compatibility..."
  mkdir -p /opt/ffmpeg
  ln -sfn /usr/local /opt/ffmpeg/dist
fi

# [FIX] Set the PKG_CONFIG_PATH environment variable.
# This is the crucial step that allows CMake to find system libraries like FFmpeg on Ubuntu.
export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/lib/$(uname -i)-linux-gnu/pkgconfig:${PKG_CONFIG_PATH}"

# Now, running cmake will succeed because it can find the correct paths.
cmake \
    ${OPENCV_BUILD_ARGS} \
    -DOPENCV_EXTRA_MODULES_PATH=/opt/opencv_contrib/modules \
    ../

echo "Building C++ Debian packages..."
make -j$(nproc)
make install
make package

# upload packages to apt server
mkdir -p /tmp/debs/
cp *.deb /tmp/debs/

tarpack upload OpenCV-${OPENCV_VERSION} /tmp/debs/ || echo "failed to upload tarball"
echo "installed" > "$TMP/.opencv"
