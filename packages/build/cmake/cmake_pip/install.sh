#!/usr/bin/env bash
set -ex
# Try with the default index first, fallback to PyPI if it fails
uv pip install --force-reinstall --default-index "${PIP_INDEX_URL:-https://pypi.org/simple}" "cmake${1:-<4}" || \
  uv pip install --force-reinstall --default-index https://pypi.org/simple "cmake${1:-<4}"

cmake --version
which cmake

update-alternatives --force --install /usr/bin/cmake cmake "$(which cmake)" 100

ls -ll /usr/bin/cmake*

# Held packages were changed and -y was used without --allow-change-held-packages
#apt-get update
#apt-mark hold cmake
#apt-get clean
#rm -rf /var/lib/apt/lists/*
