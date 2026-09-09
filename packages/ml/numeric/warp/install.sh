#!/usr/bin/env bash
echo "Installing NVIDIA Warp $WARP_VERSION"
set -ex
cd $TMP

WARP_REPO="${WARP_REPO:=https://github.com/NVIDIA/warp}"

# Try with the default index first, fallback to PyPI if it fails
uv pip install --default-index "${PIP_INDEX_URL:-https://pypi.org/simple}" usd-core matplotlib pyglet || \
  uv pip install --default-index https://pypi.org/simple usd-core matplotlib pyglet

if [ $WARP_INSTALL == "nightly" ]; then
  echo "install nightly"
else
  wget $WGET_FLAGS $WARP_INSTALL
  # Try with the default index first, fallback to PyPI if it fails
  uv pip install --default-index "${PIP_INDEX_URL:-https://pypi.org/simple}" *.whl || \
    uv pip install --default-index https://pypi.org/simple *.whl
fi

git clone --recursive --depth=1 $WARP_REPO $SRC -b v$WARP_VERSION || \
git clone --recursive --depth=1 $WARP_REPO $SRC
